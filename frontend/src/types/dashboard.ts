export type ScoreKey =
  | "crypto_affinity"
  | "token_receptivity"
  | "builder_signal"
  | "open_source_footprint"
  | "social_leverage"
  | "risk"
  | "confidence";

export type DashboardRow = {
  launch_id: string;
  activity_id: string;
  token_name: string;
  token_symbol: string;
  chain: string;
  token_address: string;
  launch_website_url: string;
  tweet_url: string;
  launched_at: string | null;
  discovered_at: string;
  launch_stage: string;
  launch_error: string | null;
  account_id: string | null;
  username: string | null;
  identity_source: string | null;
  identity_confidence: number | null;
  profile_url: string | null;
  display_name: string | null;
  profile_description: string | null;
  followers: number | null;
  following: number | null;
  statuses: number | null;
  profile_website_url: string | null;
  avatar_url: string | null;
  x_posts_collected: number | null;
  x_posts_target: number | null;
  interaction_json: Record<string, number> | null;
  account_stage: string | null;
  account_error: string | null;
  archetype: string | null;
  verdict: string | null;
  summary: string | null;
  scores_json: Partial<Record<ScoreKey, number>> | null;
  reasons_json: string[] | null;
  risks_json: string[] | null;
  evidence_json: string[] | null;
  model: string | null;
  github_repos_json: GithubRepo[];
  recent_posts_json: RecentPost[];
};

export type GithubRepo = {
  canonical_url: string;
  source: string;
  full_name: string;
  description: string;
  stars: number;
  forks: number;
  language: string;
  pushed_at: string;
  license_spdx: string;
  score: number;
  score_breakdown: Record<string, number>;
};

export type RecentPost = {
  tweet_id: string;
  url: string;
  text: string;
  created_at: string;
  likes: number;
  reposts: number;
  replies: number;
  views: number;
};

