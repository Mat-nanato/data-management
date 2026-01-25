import express from "express";

const app = express();
app.use(express.json());

let cachedLatestInfo = null;

// 動作確認用
app.get("/", (req, res) => {
  res.send("Render display server running");
});

// Mac から受け取る
app.post("/update-latest-info", (req, res) => {
  cachedLatestInfo = req.body;
  console.log("✅ data updated");
  res.json({ status: "ok" });
});

// アプリ・外部公開用
app.get("/latest-info", (req, res) => {
  if (!cachedLatestInfo) {
    return res.status(503).json({ error: "no data yet" });
  }
  res.json(cachedLatestInfo);
});

app.listen(process.env.PORT || 3000, () => {
  console.log("Render display server running");
});

