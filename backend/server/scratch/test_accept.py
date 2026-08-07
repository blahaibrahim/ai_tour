import os
import sys
import json
from dotenv import load_dotenv
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
load_dotenv()

from routes.itinerary import accept_itinerary
from flask import Flask, request

app = Flask(__name__)
app.register_blueprint(accept_itinerary.__globals__['itinerary_bp'])

def run_test():
    # first fetch a valid job from db
    import ingestion.supabase_admin
    admin = ingestion.supabase_admin.get_admin_client()
    res = admin.table("route_jobs").select("*").limit(1).execute()
    if not res.data:
        print("No jobs found")
        return
    job = res.data[0]
    
    with app.test_request_context(
        '/api/itinerary/accept', 
        method='POST',
        json={
            "job_id": job["id"],
            "accepted_stops": [{"location_id": "test"}]
        }
    ):
        from rate_limit import authenticate_and_rate_limit
        import routes.itinerary
        
        class MockUser:
            id = job["user_id"]
            
        def mock_auth(*args, **kwargs):
            return MockUser(), None
            
        routes.itinerary.authenticate_and_rate_limit = mock_auth
        
        try:
            res = routes.itinerary.accept_itinerary()
            print("Response:", res[0].get_data(as_text=True) if isinstance(res, tuple) else res.get_data(as_text=True))
        except Exception as e:
            print("Exception:", e)

if __name__ == '__main__':
    run_test()
