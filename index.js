import express from "express";
import fetch from "node-fetch";

const app = express();
const PORT = process.env.PORT || 3000;

app.get("/health", (_, res) => {
  res.json({ status: "ok" });
});

app.get("/fetch", async (_, res) => {
  const r = await fetch("https://www.family.co.jp/");
  const html = await r.text();
  res.json({
    length: html.length
  });
});

app.listen(PORT, () => {
  console.log("Server running on", PORT);
});
