from flask import Flask, jsonify
from flask_cors import CORS
import requests
import time
import os

app = Flask(__name__)
CORS(app, resources={r"/*": {"origins": "*"}})

# Cache: { base_currency: { "data": ..., "timestamp": ... } }
CACHE = {}
CACHE_TIMEOUT = 60 * 60 * 8  # 8 hours

# Get MetalPriceAPI key from environment variable
API_KEY = os.getenv("API_KEY")
if not API_KEY:
    raise Exception("API_KEY environment variable not set")

# List of metals to fetch
METALS = ['XAU', 'XAG', 'XPT', 'XPD']

@app.route("/")
def home():
    return "✅ Metal Price API is live! Visit /prices/USD to get metal rates in USD."

@app.route("/prices/<base_currency>")
def get_prices(base_currency):
    base_currency = base_currency.upper()
    current_time = time.time()

    # Return cached result if still valid
    if base_currency in CACHE and current_time - CACHE[base_currency]["timestamp"] < CACHE_TIMEOUT:
        return jsonify(CACHE[base_currency]["data"])

    # Build API request
    url = f"https://api.metalpriceapi.com/v1/latest?api_key={API_KEY}&base={base_currency}&currencies={','.join(METALS)}"

    try:
        response = requests.get(url)
        print(f"API request for {base_currency}: {response.text}")  # Debug
        data = response.json()

        if data.get("success"):
            rates = data.get("rates", {})

            # Convert to "USDXAU": price format (inverted for USD per ounce)
            formatted_rates = {}
            for metal, value in rates.items():
                if value != 0:
                    inverted_price = 1 / value  # get USD per ounce
                    formatted_rates[f"{base_currency}{metal}"] = inverted_price

            # Save formatted rates to cache
            CACHE[base_currency] = {
                "data": formatted_rates,
                "timestamp": current_time
            }

            return jsonify(formatted_rates)

        else:
            return jsonify({"error": data.get("error", "Unknown error")}), 500

    except Exception as e:
        return jsonify({"error": str(e)}), 500


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))  # Render sets PORT env var
    app.run(host="0.0.0.0", port=port)
