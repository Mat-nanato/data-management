import express from "express";
import puppeteer from "puppeteer";
import fetch from "node-fetch";
import fs from "fs";

const app = express();
const PORT = process.env.PORT || 3000;

app.use(express.json());

// ==============================
// Swift → Render : 完成原稿 保存 / 取得
// ==============================
const LATEST_TEXT_FILE = "latest-info.txt";

app.post("/save-text", (req, res) => {
  const { text } = req.body;
  if (!text) return res.status(400).json({ error: "no text" });

  try {
    fs.writeFileSync(LATEST_TEXT_FILE, text, "utf8");
    console.log("✅ latest-text saved");
    res.json({ ok: true });
  } catch (err) {
    console.error("❌ failed to save latest-text:", err);
    res.status(500).json({ error: "failed" });
  }
});

app.get("/latest-text", (_, res) => {
  try {
    res.setHeader("Cache-Control", "no-store");
    const text = fs.existsSync(LATEST_TEXT_FILE)
      ? fs.readFileSync(LATEST_TEXT_FILE, "utf8")
      : "";
    res.json({ text });
  } catch (err) {
    console.error("❌ failed to read latest-text:", err);
    res.status(500).json({ error: "failed" });
  }
});

// ==============================
// Swift → Render : キャンペーン本文 保存 / 取得
// ==============================
const CAMPAIGN_TEXT_FILE = "latest-campaign.txt";

app.post("/save-campaign-text", (req, res) => {
  const { text } = req.body;
  if (!text) return res.status(400).json({ error: "no text" });

  try {
    fs.writeFileSync(CAMPAIGN_TEXT_FILE, text, "utf8");
    console.log("✅ campaign-text saved");
    res.json({ ok: true });
  } catch (err) {
    console.error("❌ failed to save campaign-text:", err);
    res.status(500).json({ error: "failed" });
  }
});

app.get("/campaign-text", (_, res) => {
  try {
    res.setHeader("Cache-Control", "no-store");
    const text = fs.existsSync(CAMPAIGN_TEXT_FILE)
      ? fs.readFileSync(CAMPAIGN_TEXT_FILE, "utf8")
      : "";
    res.json({ text });
  } catch (err) {
    console.error("❌ failed to read campaign-text:", err);
    res.status(500).json({ error: "failed" });
  }
});

// ==============================
// FamilyMart 最新情報取得API
// ==============================
app.get("/latest-info", async (_, res) => {
  console.log("🔥 /latest-info request received");
  let browser;

  try {
    browser = await puppeteer.launch({
      headless: true,
      args: ["--no-sandbox", "--disable-setuid-sandbox"]
    });

    const page = await browser.newPage();

    // FamilyMart に弾かれないようUserAgentセット
    await page.setUserAgent(
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
      "AppleWebKit/537.36 (KHTML, like Gecko) " +
      "Chrome/120.0.0.0 Safari/537.36"
    );
    await page.setExtraHTTPHeaders({ "Accept-Language": "ja-JP,ja;q=0.9" });
    console.log("✅ after setUserAgent");

    // ==== 新商品情報 ====
    await page.goto("https://www.family.co.jp/goods/newgoods.html", {
      waitUntil: "domcontentloaded",
      timeout: 60000
    });
    await new Promise(r => setTimeout(r, 2000)); // ページ描画待ち

    const newGoodsText = await page.evaluate(() => document.body.innerText);
    const lines = newGoodsText
      .split("\n")
      .map(l => l.trim())
      .filter(Boolean);

    const products = [];
    for (let i = 0; i < lines.length; i++) {
      const m = lines[i].match(/([0-9,]+)円/);
      if (m) {
        const price = m[1].replace(/,/g, "");
        const title = i > 0 ? lines[i - 1] : "";
        products.push({ name: title, price: `${price}円` });
      }
    }

    // ==== キャンペーン情報 ====
    await page.goto("https://www.family.co.jp/campaign.html", {
      waitUntil: "domcontentloaded",
      timeout: 60000
    });
    await new Promise(r => setTimeout(r, 2000));

    const campaigns = await Promise.race([
      page.evaluate(() => {
        const results = [];
        const seen = new Set();
        document.querySelectorAll("a[href]").forEach(a => {
          const title = a.innerText?.trim();
          const url = a.href;
          if (title && title.length > 10 && url.includes("/campaign") && !seen.has(title)) {
            seen.add(title);
            results.push({ title, url });
          }
        });
        return results;
      }),
      new Promise((_, reject) =>
        setTimeout(() => reject(new Error("campaign evaluate timeout")), 10000)
      )
    ]);

    console.log("🧪 products:", products.length);
    console.log("🧪 campaigns:", campaigns.length);

    // 🔹 Render にキャンペーン本文を保存
    const campaignPlainText = campaigns.map(c => c.title).join("\n");
    await fetch("https://data-management-2.onrender.com/save-campaign-text", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        source: "familymart",
        fetchedAt: new Date().toISOString(),
        text: campaignPlainText
      })
    });

    res.json({ products, campaigns });

  } catch (err) {
    console.error("❌ Puppeteer error:", err);
    res.status(500).json({ products: [], campaigns: [], error: "Failed to fetch" });
  } finally {
    if (browser) {
      await browser.close();
      console.log("🧹 browser closed");
    }
  }
});

app.listen(PORT, () => {
  console.log(`🚀 Server running on http://localhost:${PORT}`);
});

