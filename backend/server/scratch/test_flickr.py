import requests
import json
import urllib.parse

def test():
    query = "Casbah Algiers"
    # Format tags by taking top words
    tags = ",".join(query.replace("of", "").split())
    url = f"https://www.flickr.com/services/feeds/photos_public.gne?tags={urllib.parse.quote(tags)}&format=json&nojsoncallback=1"
    headers = {"User-Agent": "Mozilla/5.0"}
    resp = requests.get(url, headers=headers)
    print("Status:", resp.status_code)
    try:
        data = resp.json()
        items = data.get("items", [])
        if items:
            img = items[0]
            print("Found image:", img["media"]["m"])
            print("Author:", img["author"])
        else:
            print("No items")
    except Exception as e:
        print(e)

if __name__ == '__main__':
    test()
