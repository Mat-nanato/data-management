import express from "express";
import puppeteer from "puppeteer";

const app = express();
const PORT = process.env.PORT || 3000;

// ==============================
// FamilyMart 最新情報取得API
// ==============================
app.get("/latest-info", async (_, res) => {
  let browser;

  try {
    browser = await puppeteer.launch({
      headless: "new",
      args: ["--no-sandbox", "--disable-setuid-sandbox"]
    });

    const page = await browser.newPage();

    // ===== 新商品 =====
    await page.goto("https://www.family.co.jp/goods/newgoods.html", {
      waitUntil: "networkidle2",
      timeout: 60000
    });

    const products = await page.evaluate(() => {
      const items = [];
      document.querySelectorAll(".ly-mod-goodslist-item").forEach(el => {
        const name = el
          .querySelector(".ly-mod-goodslist-name")
          ?.innerText?.trim();
        const price = el
          .querySelector(".ly-mod-goodslist-price")
          ?.innerText?.trim();

        if (name && price) {
          items.push({ name, price });
        }
      });
      return items;
    });

    // ===== キャンペーン =====
    await page.goto("https://www.family.co.jp/campaign.html", {
      waitUntil: "networkidle2",
      timeout: 60000
    });

    const campaigns = await page.evaluate(() => {
      const list = [];
      document.querySelectorAll("a").forEach(a => {
        const title = a.innerText?.trim();
        const url = a.href;

        if (
          title &&
          title.length > 10 &&
          url &&
          url.includes("/campaign/")
        ) {
          list.push({ title, url });
        }
      });
      return list;
    });

    await browser.close();

    res.json({ products, campaigns });

  } catch (err) {
    console.error("❌ Puppeteer error:", err);
    if (browser) await browser.close();

    res.status(500).json({
      products: [],
      campaigns: [],
      error: "failed"
    });
  }
});

// ==============================
app.listen(PORT, () => {
  console.log(`🚀 Server running on http://localhost:${PORT}`);
});

