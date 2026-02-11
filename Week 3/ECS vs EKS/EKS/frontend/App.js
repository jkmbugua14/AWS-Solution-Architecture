import React, { useEffect, useState } from "react";

function App() {
  const [data, setData] = useState({ status: "Loading...", db_version: "" });
  const [error, setError] = useState(null);

  useEffect(() => {
    // Logic: The browser calls its own /api path.
    // Nginx (on Port 80) proxies this to backend (on Port 8080).
    fetch("/api/status")
      .then((response) => {
        if (!response.ok)
          throw new Error(`HTTP error! status: ${response.status}`);
        return response.json();
      })
      .then((json) => setData(json))
      .catch((err) => {
        console.error("Integration Error:", err);
        setError(err.message);
      });
  }, []);

  return (
    <div
      style={{
        backgroundColor: "#0d1117",
        color: "#c9d1d9",
        minHeight: "100vh",
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
        fontFamily: "monospace",
      }}
    >
      <h1 style={{ color: "#58a6ff" }}>
        Astral Byte Microservices Architecture
      </h1>

      <div
        style={{
          border: "1px solid #30363d",
          padding: "30px",
          borderRadius: "10px",
          backgroundColor: "#161b22",
          boxShadow: "0 4px 10px rgba(0,0,0,0.5)",
        }}
      >
        <h2>System Connectivity Status:</h2>
        <hr style={{ borderColor: "#30363d" }} />

        {error ? (
          <p style={{ color: "#f85149" }}>⚠️ Error: {error}</p>
        ) : (
          <>
            <p>
              Frontend: <span style={{ color: "#7ee787" }}>ONLINE</span>
            </p>
            <p>
              Backend Service:{" "}
              <span style={{ color: "#7ee787" }}>{data.status}</span>
            </p>
            <p>Database Version:</p>
            <pre
              style={{
                backgroundColor: "#0d1117",
                padding: "10px",
                borderRadius: "5px",
                color: "#d2a8ff",
              }}
            >
              {data.db_version || "Waiting for data..."}
            </pre>
          </>
        )}
      </div>
      <footer
        style={{ marginTop: "20px", fontSize: "0.8rem", color: "#8b949e" }}
      >
        Service Discovery: backend:8080 (Local) / backend.internal (AWS)
      </footer>
    </div>
  );
}

export default App;
