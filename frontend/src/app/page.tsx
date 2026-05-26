"use client";

import { useEffect, useState, useTransition } from "react";
import { Activity, Brain, ExternalLink, GitBranch, Radar, Search, Sparkles, Timer } from "lucide-react";

import { loadDashboardRows } from "@/lib/dashboard";
import type { DashboardRow, ScoreKey } from "@/types/dashboard";

const POLL_MS = 5_000;

const scoreLabels: Array<[ScoreKey, string]> = [
  ["crypto_affinity", "Crypto Affinity"],
  ["token_receptivity", "Token Receptivity"],
  ["builder_signal", "Builder Signal"],
  ["open_source_footprint", "Open-source"],
  ["social_leverage", "Social Leverage"],
  ["risk", "Risk"],
  ["confidence", "Confidence"]
];

const stageText: Record<string, string> = {
  discovered: "Searching for new tokens",
  identity_resolved: "Resolving recipient identity",
  x_fetching: "Fetching X history",
  x_fetched: "Reading account behavior",
  github_scanning: "Scanning GitHub signals",
  github_scanned: "Preparing account evidence",
  ai_analyzing: "Thinking about account fit",
  completed: "Assessment complete",
  failed: "Needs attention"
};

function compactAddress(value: string | null | undefined) {
  if (!value) return "unknown";
  if (value.length <= 16) return value;
  return `${value.slice(0, 8)}...${value.slice(-6)}`;
}

function formatNumber(value: number | null | undefined) {
  const safe = Number(value ?? 0);
  if (safe >= 1_000_000) return `${(safe / 1_000_000).toFixed(1)}M`;
  if (safe >= 1_000) return `${(safe / 1_000).toFixed(1)}K`;
  return String(safe);
}

function stageFor(row: DashboardRow) {
  return row.account_stage || row.launch_stage || "discovered";
}

function rowKey(row: DashboardRow) {
  return `${row.launch_id}-${row.account_id ?? "pending"}`;
}

export default function Home() {
  const [rows, setRows] = useState<DashboardRow[]>([]);
  const [selectedKey, setSelectedKey] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [lastUpdated, setLastUpdated] = useState<Date | null>(null);
  const [isPending, startTransition] = useTransition();

  useEffect(() => {
    let alive = true;

    async function refresh() {
      try {
        const nextRows = await loadDashboardRows(80);
        if (!alive) return;
        startTransition(() => {
          setRows(nextRows);
          setSelectedKey((current) => {
            if (current && nextRows.some((row) => rowKey(row) === current)) return current;
            const firstReady = nextRows.find((row) => row.account_id) ?? nextRows[0];
            return firstReady ? rowKey(firstReady) : null;
          });
          setError(null);
          setLastUpdated(new Date());
        });
      } catch (err) {
        if (!alive) return;
        setError(err instanceof Error ? err.message : "Failed to load dashboard data");
      }
    }

    void refresh();
    const timer = window.setInterval(refresh, POLL_MS);
    return () => {
      alive = false;
      window.clearInterval(timer);
    };
  }, []);

  const selected = rows.find((row) => rowKey(row) === selectedKey) ?? rows.find((row) => row.account_id) ?? rows[0];
  const stage = selected ? stageFor(selected) : "discovered";

  return (
    <main className="shell">
      <header className="topbar">
        <div className="brand">
          <div className="brand-mark">
            <Radar size={22} />
          </div>
          <div>
            <h1>DETECT</h1>
            <p>Permissionless token recipient intelligence</p>
          </div>
        </div>
        <div className="live-pill">
          <span className="pulse" />
          <span>{isPending ? "Syncing Supabase signal" : stageText[stage] ?? "Watching Bankr launches"}</span>
        </div>
      </header>

      <section className="grid">
        <aside className="feed">
          <div className="feed-head">
            <div>
              <h2>Latest launches</h2>
              <span className="muted">{rows.length} visible signals</span>
            </div>
            <Search size={18} />
          </div>
          <div className="token-list">
            {rows.map((row) => {
              const key = rowKey(row);
              return (
                <button
                  key={key}
                  className={`token-card ${rowKey(selected) === key ? "active" : ""}`}
                  onClick={() => setSelectedKey(key)}
                  type="button"
                >
                  <div className="token-line">
                    <span className="ticker">${row.token_symbol || "TOKEN"}</span>
                    <span className="stage">
                      <span className="stage-dot" />
                      {stageText[stageFor(row)] ?? stageFor(row)}
                    </span>
                  </div>
                  <div className="token-meta">
                    <span>{row.chain || "unknown chain"}</span>
                    <span>{compactAddress(row.token_address)}</span>
                    <span>@{row.username || "resolving"}</span>
                  </div>
                </button>
              );
            })}
            {!rows.length && (
              <div className="empty">
                {error ? `Dashboard load failed: ${error}` : "No launches yet. The worker will fill this view as it runs."}
              </div>
            )}
          </div>
        </aside>

        <section className="detail" id={selected?.launch_id}>
          <div className="detail-head">
            <div>
              <h2>{selected ? `$${selected.token_symbol || "TOKEN"} recipient intelligence` : "Waiting for data"}</h2>
              <span className="muted">
                {lastUpdated ? `Live Supabase sync every ${POLL_MS / 1000}s / ${lastUpdated.toLocaleTimeString()}` : "Preparing live sync"}
              </span>
            </div>
            <Activity size={18} />
          </div>

          {selected ? <Detail row={selected} /> : <div className="empty">Start the backend worker to generate account intelligence.</div>}
        </section>
      </section>
    </main>
  );
}

function Detail({ row }: { row: DashboardRow }) {
  const scores = row.scores_json ?? {};
  const stage = stageFor(row);
  const interactions = row.interaction_json ?? {};
  const repos = row.github_repos_json ?? [];
  const posts = row.recent_posts_json ?? [];

  return (
    <div className="detail-body">
      <div className="hero-row">
        <div className="account-panel">
          <div className="identity">
            {row.avatar_url ? <img className="avatar" src={row.avatar_url} alt="" /> : <div className="avatar" />}
            <div>
              <h2>@{row.username || "resolving"}</h2>
              <div className="muted">{row.display_name || row.identity_source || "Waiting for identity resolution"}</div>
            </div>
          </div>
          <p className="summary">
            {row.summary ||
              "The backend is collecting X history, scanning GitHub signals, and preparing an English assessment for this recipient."}
          </p>
          <div className="verdict">
            <Sparkles size={15} />
            {row.verdict ? row.verdict.replaceAll("_", " ") : "analysis pending"}
          </div>
        </div>

        <div className="thinking-panel">
          <ul className="thinking-list">
            <li>
              <span>Launch stage</span>
              <strong>{row.launch_stage}</strong>
            </li>
            <li>
              <span>Account stage</span>
              <strong>{stage}</strong>
            </li>
            <li>
              <span>X history</span>
              <strong>
                {row.x_posts_collected ?? 0}/{row.x_posts_target ?? 50}
              </strong>
            </li>
            <li>
              <span>Model</span>
              <strong>{row.model || "pending"}</strong>
            </li>
          </ul>
        </div>
      </div>

      <div className="score-grid">
        {scoreLabels.map(([key, label]) => {
          const value = Math.max(0, Math.min(100, Number(scores[key] ?? 0)));
          return (
            <div className="score-row" key={key}>
              <div className="score-label">
                <span>{label}</span>
                <strong>{value}</strong>
              </div>
              <div className="bar">
                <span style={{ width: `${value}%` }} />
              </div>
            </div>
          );
        })}
      </div>

      <div className="section-grid">
        <div className="metric-panel">
          <h3>Recipient Surface</h3>
          <div className="facts">
            <div className="fact">
              <strong>{formatNumber(row.followers)}</strong>
              <span>Followers</span>
            </div>
            <div className="fact">
              <strong>{formatNumber(interactions.median_likes)}</strong>
              <span>Median likes</span>
            </div>
            <div className="fact">
              <strong>{formatNumber(interactions.median_reposts)}</strong>
              <span>Median reposts</span>
            </div>
            <div className="fact">
              <strong>{formatNumber(interactions.median_views)}</strong>
              <span>Median views</span>
            </div>
          </div>
        </div>

        <div className="metric-panel">
          <h3>Token Context</h3>
          <div className="facts">
            <div className="fact">
              <strong>{row.chain || "unknown"}</strong>
              <span>Chain</span>
            </div>
            <div className="fact">
              <strong>{compactAddress(row.token_address)}</strong>
              <span>Contract</span>
            </div>
            <div className="fact">
              <strong>{row.identity_source || "pending"}</strong>
              <span>Identity source</span>
            </div>
            <div className="fact">
              <strong>{row.identity_confidence ?? 0}</strong>
              <span>Source confidence</span>
            </div>
          </div>
        </div>

        <div className="evidence-panel">
          <h3>
            <Brain size={15} /> Analysis Reasons
          </h3>
          <ul className="plain-list">
            {(row.reasons_json?.length ? row.reasons_json : ["Analysis is still being generated."]).map((reason) => (
              <li key={reason}>{reason}</li>
            ))}
          </ul>
        </div>

        <div className="evidence-panel">
          <h3>
            <Timer size={15} /> Risks
          </h3>
          <ul className="plain-list">
            {(row.risks_json?.length ? row.risks_json : ["No risk notes yet."]).map((risk) => (
              <li key={risk}>{risk}</li>
            ))}
          </ul>
        </div>

        <div className="evidence-panel">
          <h3>
            <GitBranch size={15} /> GitHub Signals
          </h3>
          <div className="repo-list">
            {repos.length ? (
              repos.map((repo) => (
                <a className="repo" href={repo.canonical_url} key={repo.canonical_url} target="_blank">
                  <strong>
                    {repo.full_name} <ExternalLink size={13} />
                  </strong>
                  <span className="muted">
                    {repo.source} / score {repo.score} / {repo.stars} stars / {repo.language || "unknown"}
                  </span>
                </a>
              ))
            ) : (
              <span className="muted">No GitHub signal found yet.</span>
            )}
          </div>
        </div>

        <div className="evidence-panel">
          <h3>Recent X Evidence</h3>
          <ul className="plain-list">
            {posts.length ? posts.map((post) => <li key={post.tweet_id}>{post.text}</li>) : <li>No posts collected yet.</li>}
          </ul>
        </div>
      </div>
    </div>
  );
}
