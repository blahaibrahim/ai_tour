import os
import sys
import json
from dotenv import load_dotenv
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
load_dotenv()

from routes.itinerary import generate_itinerary
from flask import Flask, request

app = Flask(__name__)
app.register_blueprint(generate_itinerary.__globals__['itinerary_bp'])

def run_test():
    with app.test_request_context(
        '/api/itinerary', 
        method='POST',
        json={
            "lat": 36.7538,
            "lng": 3.0588,
            "radius_km": 5,
            "prompt": "I want to see historical monuments and museums",
            "wanted_visits": 4
        }
    ):
        # We must bypass rate limit check by mocking user
        from rate_limit import authenticate_and_rate_limit
        import routes.itinerary
        
        class MockUser:
            id = None
            
        def mock_auth(*args, **kwargs):
            import ingestion.supabase_admin
            admin = ingestion.supabase_admin.get_admin_client()
            user_res = admin.table("users").select("id").limit(1).execute()
            if user_res.data:
                MockUser.id = user_res.data[0]["id"]
            return MockUser(), None
            
        routes.itinerary.authenticate_and_rate_limit = mock_auth
        
        try:
            res = routes.itinerary.generate_itinerary()
            print("Response:", res[0].get_data(as_text=True) if isinstance(res, tuple) else res.get_data(as_text=True))
        except Exception as e:
            print("Exception:", e)

if __name__ == '__main__':
    run_test()
