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

# You can adjust which metals you want
METALS = ['XAU', 'XAG', 'XPT', 'XPD']
BASE = 'USD'

@app.route("/prices")
def get_prices():
    current_time = time.time()

    if "data" in CACHE and current_time - CACHE["timestamp"] < CACHE_TIMEOUT:
        return jsonify(CACHE["data"])

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
    app.run(debug=True)
