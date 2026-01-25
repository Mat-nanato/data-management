import express from "express";

const app = express();
app.use(express.json());

let latestCache = null;

// Mac側から結果を送る用
app.post("/push", (req, res) => {
  latestCache = req.body;
  res.json({ ok: true });
});

// 不特定多数が見る用
app.get("/latest-info", (req, res) => {
  if (!latestCache) {
    return res.status(503).json({ error: "no data yet" });
  }
  res.json(latestCache);
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log("Render display server running");
});

