import os
import sys
from dotenv import load_dotenv
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
load_dotenv()

def run_test():
    import ingestion.supabase_admin
    admin = ingestion.supabase_admin.get_admin_client()
    res = admin.table("route_jobs").select("*").order("created_at", desc=True).limit(3).execute()
    for job in res.data:
        print(f"Job ID: {job['id']}, Prompt: {job['prompt']}")
        # The app might have sent wanted_visits in the original request to /api/itinerary
        # Let's see if we can deduce what wanted_visits was from result_data
        result = job.get("result_data")
        if result and "stops" in result:
            print(f"Number of stops: {len(result['stops'])}")

if __name__ == '__main__':
    run_test()
