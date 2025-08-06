from flask import Flask, jsonify
import requests
import time
import os

app = Flask(__name__)

# Cache to prevent repeated API hits
CACHE = {}
CACHE_TIMEOUT = 60 * 5  # 5 minutes

# Get your MetalPriceAPI key from environment variable
API_KEY = os.getenv("API_KEY")
if not API_KEY:
    raise Exception("API_KEY environment variable not set")

# List of metals to fetch
METALS = ['XAU', 'XAG', 'XPT', 'XPD']
BASE = 'USD'

@app.route("/")
def home():
    return "✅ Metal Price API is live! Visit /prices to get metal rates."

@app.route("/prices")
def get_prices():
    current_time = time.time()

    # Return cached result if still valid
    if "data" in CACHE and current_time - CACHE["timestamp"] < CACHE_TIMEOUT:
        return jsonify(CACHE["data"])

    # Build API request
    url = f"https://api.metalpriceapi.com/v1/latest?api_key={API_KEY}&base={BASE}&currencies={','.join(METALS)}"

    try:
        response = requests.get(url)
        data = response.json()

        if data.get("success"):
            CACHE["data"] = data
            CACHE["timestamp"] = current_time
            return jsonify(data)
        else:
            return jsonify({"error": data.get("error", "Unknown error")}), 500

    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))  # Render sets PORT env var
    app.run(host="0.0.0.0", port=port)
