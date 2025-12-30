from flask import Flask, jsonify, request
from flask_cors import CORS

app = Flask(__name__)
CORS(app)

# -----------------------------
# Health Check (MANDATORY)
# -----------------------------
@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "ok"}), 200


# -----------------------------
# Mock Data
# -----------------------------
mock_categories = [
    {"id": "classics", "name": "Classics", "description": "Timeless masterpieces from renowned authors."},
    {"id": "modern", "name": "Modern Literature", "description": "Contemporary works from modern authors."},
    {"id": "poetry", "name": "Poetry", "description": "Beautiful poetry from literary giants."},
    {"id": "fiction", "name": "Fiction", "description": "Fictional works with universal appeal."},
    {"id": "fantasy", "name": "Fantasy", "description": "Magical and fantastical stories."},
    {"id": "science", "name": "Science", "description": "Scientific exploration and discovery."}
]

mock_products = [
    {
        "id": "1",
        "name": "War and Peace",
        "author": "Leo Tolstoy",
        "price": 24.99,
        "categoryId": "classics",
        "category": "Classics",
        "description": "War and Peace is a novel by Leo Tolstoy, published in 1869.",
        "imageUrl": "/images/books/war-and-peace-leo-tolstoy.jpg",
        "pages": 1225,
        "published": 1869
    },
    {
        "id": "2",
        "name": "Anna Karenina",
        "author": "Leo Tolstoy",
        "price": 19.99,
        "categoryId": "classics",
        "category": "Classics",
        "description": "Anna Karenina is a novel by Leo Tolstoy, first published in 1878.",
        "imageUrl": "/images/books/anna-karenina-leo-tolstoy.jpg",
        "pages": 864,
        "published": 1878
    },
    {
        "id": "3",
        "name": "Crime and Punishment",
        "author": "Fyodor Dostoevsky",
        "price": 18.99,
        "categoryId": "classics",
        "category": "Classics",
        "description": "Crime and Punishment focuses on the moral dilemmas of Rodion Raskolnikov.",
        "imageUrl": "/images/books/crime-and-punishment-fyodor-dostoevsky.jpg",
        "pages": 671,
        "published": 1866
    }
]

mock_cart = []

# -----------------------------
# API Routes
# -----------------------------
@app.route("/api/categories", methods=["GET"])
def get_categories():
    return jsonify(mock_categories)


@app.route("/api/categories/<category_id>", methods=["GET"])
def get_category(category_id):
    category = next((c for c in mock_categories if c["id"] == category_id), None)
    if category:
        return jsonify(category)
    return jsonify({"error": "Category not found"}), 404


@app.route("/api/categories/<category_id>/products", methods=["GET"])
def get_products_by_category(category_id):
    products = [p for p in mock_products if p["categoryId"] == category_id]
    return jsonify(products)


@app.route("/api/products/<product_id>", methods=["GET"])
def get_product(product_id):
    product = next((p for p in mock_products if p["id"] == product_id), None)
    if product:
        return jsonify(product)
    return jsonify({"error": "Product not found"}), 404


@app.route("/api/cart", methods=["GET"])
def get_cart():
    return jsonify(mock_cart)


@app.route("/api/cart/add", methods=["POST"])
def add_to_cart():
    data = request.json
    product_id = data.get("productId")
    quantity = data.get("quantity", 1)

    product = next((p for p in mock_products if p["id"] == product_id), None)
    if not product:
        return jsonify({"error": "Product not found"}), 404

    cart_item = next((item for item in mock_cart if item["id"] == product_id), None)
    if cart_item:
        cart_item["quantity"] += quantity
    else:
        mock_cart.append({
            "id": product_id,
            "name": product["name"],
            "author": product["author"],
            "price": product["price"],
            "quantity": quantity,
            "imageUrl": product["imageUrl"]
        })

    return jsonify({"success": True})


@app.route("/api/cart/update", methods=["POST"])
def update_cart():
    data = request.json
    item_id = data.get("itemId")
    quantity = data.get("quantity")

    item = next((item for item in mock_cart if item["id"] == item_id), None)
    if not item:
        return jsonify({"error": "Item not found"}), 404

    item["quantity"] = quantity
    return jsonify({"success": True})


@app.route("/api/cart/remove/<item_id>", methods=["DELETE"])
def remove_from_cart(item_id):
    global mock_cart
    mock_cart = [item for item in mock_cart if item["id"] != item_id]
    return jsonify({"success": True})


@app.route("/api/cart/checkout", methods=["POST"])
def checkout():
    global mock_cart
    mock_cart = []
    return jsonify({"success": True})


# -----------------------------
# Local Development Only
# -----------------------------
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
