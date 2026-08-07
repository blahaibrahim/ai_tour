import requests
import re

def test():
    query = "Casbah of Algiers"
    url = "https://html.duckduckgo.com/html/"
    headers = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"}
    resp = requests.post(url, data={"q": query, "kl": "us-en"}, headers=headers)
    print("Length:", len(resp.text))
    # In DDG HTML, thumbnails are like //external-content.duckduckgo.com/iu/?u=URL
    urls = re.findall(r'external-content\.duckduckgo\.com/iu/\?u=([^&]+)', resp.text)
    from urllib.parse import unquote
    urls = [unquote(u) for u in urls]
    print("Extracted:", urls[:5])

if __name__ == '__main__':
    test()
