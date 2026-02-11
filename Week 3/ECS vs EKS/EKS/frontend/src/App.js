import { useEffect, useState } from "react";

function App() {
  const [data, setData] = useState({
    status: "In Syncing Mode...",
    db_version: "",
  });
  const [error, setError] = useState(null);

  useEffect(() => {
    fetch("/api/status")
      .then((response) => {
        if (!response.ok)
          throw new Error(`Packet dropped! HTTP status: ${response.status}`);
        return response.json();
      })
      .then((json) => setData(json))
      .catch((err) => {
        console.error("Transmission Error:", err);
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
        fontFamily: "'Courier New', Courier, monospace",
      }}
    >
      <h1 style={{ color: "#58a6ff", textShadow: "0 0 10px #58a6ff" }}>
        // COMMAND CENTER //
      </h1>

      <div
        style={{
          border: "2px solid #30363d",
          padding: "40px",
          borderRadius: "15px",
          backgroundColor: "#161b22",
          boxShadow: "0 0 20px rgba(88, 166, 255, 0.2)",
          width: "80%",
          maxWidth: "600px",
        }}
      >
        <h2 style={{ marginBottom: "20px" }}>$ system diagnostics --all</h2>
        <hr style={{ borderColor: "#30363d", marginBottom: "20px" }} />

        {error ? (
          <div
            style={{
              color: "#f85149",
              padding: "10px",
              border: "1px solid #f85149",
            }}
          >
            <h2>⚠️ CRITICAL FAILURE: System link broken.</h2>
          </div>
        ) : (
          <>
            <p style={{ margin: "10px 0" }}>
              [ INGRESS ] Frontend Node:{" "}
              <span style={{ color: "#7ee787", fontWeight: "bold" }}>
                FULLY OPERATIONAL
              </span>
            </p>
            <p style={{ margin: "10px 0" }}>
              [ LOGIC ] Backend API:{" "}
              <span style={{ color: "#7ee787" }}>
                {data.status.toUpperCase()}
              </span>
            </p>
            <p style={{ marginTop: "20px" }}>
              [ PERSISTENCE ] Database_Kernel_Version:
            </p>
            <pre
              style={{
                backgroundColor: "#0d1117",
                padding: "15px",
                borderRadius: "8px",
                color: "#d2a8ff",
                borderLeft: "4px solid #d2a8ff",
                overflowX: "auto",
              }}
            >
              {data.db_version || "Requesting payload from database..."}
            </pre>
          </>
        )}
      </div>
    </div>
  );
}

export default App;
