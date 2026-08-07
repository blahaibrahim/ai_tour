from duckduckgo_search import DDGS
import json

def test():
    with DDGS() as ddgs:
        results = list(ddgs.images("Casbah of Algiers", max_results=1))
        print(json.dumps(results, indent=2))

if __name__ == '__main__':
    test()
