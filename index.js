// index.js（Render 側）
import express from "express";
import fs from "fs";

const app = express();
app.use(express.json());

app.post("/save-text", (req, res) => {
  const text = req.body.text;

  if (!text) {
    return res.status(400).json({ error: "no text" });
  }

  fs.writeFileSync("latest-info.txt", text, "utf8");
  console.log("✅ Swift からテキスト保存");

  res.json({ ok: true });
});

app.listen(3000, () => {
  console.log("Render server running");
});

