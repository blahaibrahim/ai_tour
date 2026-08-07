import requests
import json

def test():
    query = "Casbah of Algiers"
    url = f"https://api.qwant.com/v3/search/images?count=1&q={requests.utils.quote(query)}"
    headers = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"}
    resp = requests.get(url, headers=headers)
    print("Status:", resp.status_code)
    try:
        data = resp.json()
        print(json.dumps(data, indent=2))
    except Exception as e:
        print(e)

if __name__ == '__main__':
    test()
