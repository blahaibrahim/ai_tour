import requests
import re
import json

def test():
    query = "Casbah of Algiers"
    url = f"https://images.search.yahoo.com/search/images?p={requests.utils.quote(query)}"
    headers = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"}
    resp = requests.get(url, headers=headers)
    
    # Yahoo encodes image data in JSON inside the HTML: window.I18N = ... or img.src='...'
    # Actually yahoo stores the real URLs in data-url or inside a script tag
    # Let's search for "imgurl":"(http[^"]+)"
    urls = re.findall(r'"imgurl":"(http[^"]+)"', resp.text)
    print("Real URLs:", urls[:5])

if __name__ == '__main__':
    test()
