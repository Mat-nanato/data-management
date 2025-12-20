
import json
import requests
from bs4 import BeautifulSoup

# ファミマ新商品ページ
URL = "https://www.family.co.jp/goods/newgoods.html"

def fetch_products():
    res = requests.get(URL)
    soup = BeautifulSoup(res.text, "html.parser")

    items = soup.select(".ly-mod-infoset")
    products = []

    for item in items:
        name = item.select_one(".ly-mod-infoset-name")
        price = item.select_one(".ly-mod-infoset-price")
        region = item.select_one(".ly-mod-infoset-area")

        products.append({
            "name": name.get_text(strip=True) if name else "",
            "price": price.get_text(strip=True) if price else "",
            "region": region.get_text(strip=True) if region else "全国"
        })

    return products


def save_json(data):
    with open("family_products.json", "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


def main():
    products = fetch_products()
    save_json(products)
    print("family_products.json を生成しました！")


if __name__ == "__main__":
    main()
