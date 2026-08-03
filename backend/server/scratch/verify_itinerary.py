import os
import sys
from dotenv import load_dotenv

# Ensure backend/server is in PYTHONPATH
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# Load env variables for LLM API keys
load_dotenv()

from routes.itinerary import _order_travel_time, _expand_categories
from data.geo import get_travel_time_matrix
from llm import extract_intent

def verify():
    # 1. Test get_travel_time_matrix
    print("Testing get_travel_time_matrix...")
    coords = [(36.7538, 3.0588), (36.76, 3.06)]
    matrix = get_travel_time_matrix(coords)
    print(f"Matrix: {matrix}")
    assert matrix is not None
    
    # 2. Test _order_travel_time
    print("Testing _order_travel_time...")
    stops = [
        {"lat": 36.76, "lng": 3.06, "id": "1"},
        {"lat": 36.77, "lng": 3.07, "id": "2"}
    ]
    ordered = _order_travel_time(36.7538, 3.0588, stops)
    print(f"Ordered: {[s['id'] for s in ordered]}")
    assert len(ordered) == 2
    
    # 3. Test intent
    print("Testing extract_intent & categories...")
    intent = extract_intent("I want to see historic ruins and nature")
    print(f"Intent: {intent}")
    categories = _expand_categories(intent)
    print(f"Categories: {categories}")
    
    print("All python internal integrations verified.")

if __name__ == "__main__":
    verify()
