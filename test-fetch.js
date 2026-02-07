import fetch from "node-fetch";

async function test() {
  try {
    const res = await fetch("https://data-management-2.onrender.com/update-latest-info", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ test: "ok" })
    });
    const json = await res.json();
    console.log("✅ Render にキャッシュ送信完了", json);
  } catch (e) {
    console.error("⚠️ Render 送信失敗", e);
  }
}

test();

