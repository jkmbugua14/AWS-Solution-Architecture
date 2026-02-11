const express = require("express");
const { Pool } = require("pg");
const app = express();
const port = 8080;

// ARCHITECT'S NOTE: We pull these from process.env.
// Terraform will inject these into the container at runtime.
const pool = new Pool({
  host: process.env.DB_HOST,
  database: process.env.DB_NAME,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD, // This comes from Secrets Manager
  port: 5432,
  ssl: {
    rejectUnauthorized: false, // Required for RDS unless you bundle the AWS CA cert
  },
});

app.get("/api/status", async (req, res) => {
  try {
    const dbRes = await pool.query("SELECT version()");
    res.json({
      status: "Healthy",
      service: "Backend API",
      database: "Connected",
      db_version: dbRes.rows[0].version,
    });
  } catch (err) {
    console.error("Database connection error:", err.stack);
    res
      .status(500)
      .json({ status: "Error", message: "Database connection failed" });
  }
});

app.listen(port, "0.0.0.0", () => {
  console.log(`Backend service listening at http://0.0.0.0:${port}`);
});
