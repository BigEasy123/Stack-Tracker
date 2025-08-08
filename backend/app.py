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

    # Serve from cache if fresh
    if "data" in CACHE and current_time - CACHE["timestamp"] < CACHE_TIMEOUT:
        return jsonify(CACHE["data"])

    url = f"https://api.metalpriceapi.com/v1/latest?api_key={API_KEY}&base={BASE}&currencies={','.join(METALS)}"

    try:
        response = requests.get(url)

        # Check for valid JSON
        if "application/json" not in response.headers.get("Content-Type", ""):
            return jsonify({
                "error": "API did not return JSON",
                "body": response.text
            }), 500

        data = response.json()

        # Check for API success
        if not data.get("success"):
            return jsonify({
                "error": data.get("error", "Unknown error from API")
            }), 500

        result = {"success": True}

        # Ensure large numbers (USD per metal)
        for metal, rate in data.get("rates", {}).items():
            if rate and rate != 0:
                # Invert so we get USD per 1 unit of metal
                usd_price = 1 / rate
                result[f"USDX{metal}"] = usd_price
            else:
                result[f"USDX{metal}"] = None

        # Cache results
        CACHE["data"] = result
        CACHE["timestamp"] = current_time

        return jsonify(result)

    except Exception as e:
        return jsonify({"error": str(e)}), 500


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))
    app.run(host="0.0.0.0", port=port)
