from flask import Flask, jsonify
from flask_cors import CORS
import requests
import time
import os

app = Flask(__name__)
CORS(app, resources={r"/*": {"origins": "*"}})

CACHE = {}
CACHE_TIMEOUT = 60 * 60 * 8  # 8 hours

API_KEY = os.getenv("API_KEY")
if not API_KEY:
    raise Exception("API_KEY environment variable not set")

METALS = ['XAU', 'XAG', 'XPT', 'XPD']
BASE = 'USD'

@app.route("/")
def home():
    return "✅ Metal Price API is live! Visit /prices to get metal rates."

@app.route("/prices")
def get_prices():
    current_time = time.time()

    # Serve cached data if fresh
    if "data" in CACHE and current_time - CACHE["timestamp"] < CACHE_TIMEOUT:
        return jsonify(CACHE["data"])

    url = f"https://api.metalpriceapi.com/v1/latest?api_key={API_KEY}&base={BASE}&currencies={','.join(METALS)}"

    try:
        response = requests.get(url, timeout=10)

        # Debug log (optional)
        print("Status:", response.status_code, "Headers:", response.headers)

        if "application/json" not in response.headers.get("Content-Type", ""):
            return jsonify({
                "error": "API did not return JSON. Check API key or rate limit.",
                "status_code": response.status_code,
                "body": response.text[:200]
            }), 500

        data = response.json()

        if not data.get("success"):
            return jsonify({"error": data.get("error", "Unknown error")}), 500

        result = {"success": True, "timestamp": current_time}
        for metal, rate in data["rates"].items():
            if rate:
                result[f"USDX{metal}"] = round(1 / rate, 6)
            else:
                result[f"USDX{metal}"] = None

        # Only cache on success
        CACHE["data"] = result
        CACHE["timestamp"] = current_time

        return jsonify(result)

    except requests.exceptions.RequestException as e:
        # API/network error — serve old data if available
        if "data" in CACHE:
            return jsonify({
                "warning": "Using cached data due to API error",
                "error": str(e),
                **CACHE["data"]
            })
        return jsonify({"error": str(e)}), 500

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))
    app.run(host="0.0.0.0", port=port)
