import React, { useState } from 'react';

export default function App() {
  const [count, setCount] = useState(0);

  return (
    <div
      style={{
        fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif',
        minHeight: '100vh',
        margin: 0,
        padding: '24px',
        background: '#eef3f8',
        color: '#0f172a',
      }}
    >
      <div
        style={{
          maxWidth: 900,
          margin: '0 auto',
          background: 'rgba(255,255,255,0.78)',
          border: '1px solid rgba(255,255,255,0.8)',
          borderRadius: 18,
          padding: 24,
          boxShadow: '0 12px 30px rgba(15,23,42,0.10)',
        }}
      >
        <h1 style={{ marginTop: 0, marginBottom: 8 }}>B-Roll Downloader</h1>
        <p style={{ marginTop: 0, opacity: 0.75 }}>
          React is now running inside your Electron app.
        </p>

        <button
          onClick={() => setCount((v) => v + 1)}
          style={{
            marginTop: 12,
            borderRadius: 12,
            border: '1px solid #cbd5e1',
            background: '#ffffff',
            padding: '10px 14px',
            cursor: 'pointer',
          }}
        >
          Test button: {count}
        </button>
      </div>
    </div>
  );
}
