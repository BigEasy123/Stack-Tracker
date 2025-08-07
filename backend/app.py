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

    if "data" in CACHE and current_time - CACHE["timestamp"] < CACHE_TIMEOUT:
        return jsonify(CACHE["data"])

    url = f"https://api.metalpriceapi.com/v1/latest?api_key={API_KEY}&base={BASE}&currencies={','.join(METALS)}"

    try:
        response = requests.get(url)

        # Check if response is JSON
        if "application/json" not in response.headers.get("Content-Type", ""):
            return jsonify({"error": "API did not return JSON", "body": response.text}), 500

        data = response.json()

        if not data.get("success"):
            return jsonify({"error": data.get("error", "Unknown error")}), 500

        usd_prices = {}
        for metal, rate in data["rates"].items():
            usd_prices[f"USD{metal}"] = 1 / rate if rate else None

        result = {"success": True, "rates": usd_prices}

        CACHE["data"] = result
        CACHE["timestamp"] = current_time

        return jsonify(result)

    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))
    app.run(host="0.0.0.0", port=port)
