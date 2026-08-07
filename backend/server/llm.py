from __future__ import annotations
import json
from openai import OpenAI, APIError
from google import genai

from config import Config, require_llm_key, require_gemini_key

_groq_client: OpenAI | None = None
_gemini_client: genai.Client | None = None

class LLMError(RuntimeError):
    pass

def get_groq_client() -> OpenAI:
    global _groq_client
    if _groq_client is None:
        _groq_client = OpenAI(base_url=Config.LLM_BASE_URL, api_key=require_llm_key())
    return _groq_client

def get_gemini_client() -> genai.Client:
    global _gemini_client
    if _gemini_client is None:
        _gemini_client = genai.Client(api_key=require_gemini_key())
    return _gemini_client

def _chat_gemini(
    messages: list[dict],
    *,
    json_mode: bool,
    max_tokens: int,
    temperature: float,
    thinking_level: str,
) -> str:
    prompt = "\n".join(f"{m['role'].upper()}: {m['content']}" for m in messages)
    if json_mode:
        prompt += "\n\nCRITICAL INSTRUCTION: Return ONLY valid JSON."

    client = get_gemini_client()
    generation_config = {
        # Headroom for reasoning, but bounded by the caller's own budget — an
        # unconditional 65536 lets a model that starts rambling run for a
        # minute before anything stops it.
        'max_output_tokens': max(max_tokens * 4, 4096),
        'thinking_level': thinking_level,
        'temperature': temperature,
    }

    if json_mode:
        generation_config['response_mime_type'] = 'application/json'

    interaction = client.interactions.create(
        model='models/gemini-3-flash-preview',
        input=prompt,
        generation_config=generation_config,
    )
    content = getattr(interaction, 'output_text', getattr(interaction, 'text', ''))
    if not content:
        raise LLMError("Empty response from Gemini")

    # Optional: strip markdown json blocks if present
    if json_mode:
        content = content.strip()
        if content.startswith("```json"):
            content = content[7:]
        if content.startswith("```"):
            content = content[3:]
        if content.endswith("```"):
            content = content[:-3]

    return content.strip()


def chat(
    messages: list[dict],
    *,
    json_mode: bool = False,
    max_tokens: int = 800,
    temperature: float = 0.7,
    thinking_level: str = "medium",
    prefer: str = "gemini",
) -> str:
    """Send a chat-completion request. Both providers back each other up;
    `prefer` picks which one is tried first.

    Two latency dials, both measured on the itinerary selection prompt
    (pick 8 ids out of 30 candidates, JSON out):

      * `thinking_level` — 'minimal' 5.5s, 'low' 16.2s, 'medium' 16.1s,
        'high' 20.6s, all returning the same 8 valid ids. It was hardcoded to
        'medium' for every caller, so a constrained selection over pre-vetted
        candidates was paying full reasoning cost for nothing.
      * `prefer` — Groq answers the same prompt in ~1.6s against Gemini's 5.5s
        at its fastest. Gemini stays the default (it is the better model for
        the open-ended describe/rewrite work), but latency-critical calls on
        the user's waiting path ask for Groq first and still fall back to
        Gemini if Groq is down. Nothing loses a provider; only the order
        changes.
    """
    if prefer == "gemini":
        try:
            return _chat_gemini(
                messages, json_mode=json_mode, max_tokens=max_tokens,
                temperature=temperature, thinking_level=thinking_level,
            )
        except Exception as e:
            print(f"Gemini failed, falling back to Groq: {e}")

    # Groq — either the caller's preference, or Gemini's fallback.
    client = get_groq_client()
    kwargs: dict = {"reasoning_effort": "none"}
    if json_mode:
        kwargs["response_format"] = {"type": "json_object"}

    try:
        response = client.chat.completions.create(
            model=Config.LLM_MODEL,
            messages=messages,
            max_tokens=max_tokens,
            temperature=temperature,
            **kwargs,
        )
    except APIError as e:
        try:
            response = client.chat.completions.create(
                model=Config.LLM_MODEL,
                messages=messages,
                max_tokens=max_tokens,
                temperature=temperature,
            )
        except APIError as e2:
            print(f"Groq primary model ({Config.LLM_MODEL}) failed: {e2}")
            try:
                # Try a guaranteed Groq model if the configured one fails
                response = client.chat.completions.create(
                    model="llama-3.3-70b-versatile",
                    messages=messages,
                    max_tokens=max_tokens,
                    temperature=temperature,
                )
            except APIError as e3:
                print(f"Groq fallback model failed: {e3}")
                if prefer == "groq":
                    # Groq was first choice, so Gemini hasn't been tried yet —
                    # a preference must not cost the caller a provider.
                    print("Groq exhausted, falling back to Gemini")
                    return _chat_gemini(
                        messages, json_mode=json_mode, max_tokens=max_tokens,
                        temperature=temperature, thinking_level=thinking_level,
                    )
                raise LLMError(str(e3)) from e3

    content = response.choices[0].message.content
    if not content:
        raise LLMError("Empty response from the LLM provider")
    return content

def embed(text: str) -> list[float]:
    """Generate a vector embedding for a piece of text using Gemini."""
    try:
        from google.genai.types import EmbedContentConfig
        client = get_gemini_client()
        response = client.models.embed_content(
            model='models/gemini-embedding-2',
            contents=text,
            config=EmbedContentConfig(output_dimensionality=384)
        )
        return response.embeddings[0].values
    except Exception as e:
        print(f"Gemini embed failed: {e}")
        # Note: Groq doesn't provide embeddings, so if Gemini fails we just return an empty list or raise
        raise LLMError(f"Embedding failed: {e}")


def extract_intent(prompt: str) -> dict:
    """Extract structured intent from a user's travel prompt using Gemini."""
    client = get_gemini_client()
    
    generation_config = {
        'temperature': 1,
        'max_output_tokens': 65536,
        'top_p': 0.95,
        'thinking_level': 'high',
    }

    input_prompt = (
        "Analyze this travel prompt and extract the requested themes, activities, and category preferences. "
        "Return ONLY a valid JSON object matching this schema:\n"
        "{\n"
        "  \"themes\": [{\"name\": \"string\", \"weight\": 1.0}],\n"
        "  \"activities\": [\"string\"],\n"
        "  \"required_categories\": [\"string\"],\n"
        "  \"preferred_categories\": [\"string\"],\n"
        "  \"excluded_categories\": [\"string\"]\n"
        "}\n\n"
        f"Prompt: {prompt}"
    )

    try:
        interaction = client.interactions.create(
            model='models/gemini-3-flash-preview',
            input=input_prompt,
            generation_config=generation_config,
        )
        
        # Some SDK versions use output_text, others text
        raw_output = getattr(interaction, 'output_text', getattr(interaction, 'text', ''))
        
        from json_utils import extract_json
        return extract_json(raw_output)
    except Exception as e:
        print(f"Intent extraction failed: {e}")
        return {
            "themes": [],
            "activities": [],
            "required_categories": [],
            "preferred_categories": [],
            "excluded_categories": []
        }
