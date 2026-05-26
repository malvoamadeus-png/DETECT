CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS detect_launches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  activity_id text NOT NULL UNIQUE,
  token_name text NOT NULL DEFAULT '',
  token_symbol text NOT NULL DEFAULT '',
  chain text NOT NULL DEFAULT '',
  token_address text NOT NULL DEFAULT '',
  launch_type text NOT NULL DEFAULT '',
  launch_status text NOT NULL DEFAULT '',
  tx_hash text NOT NULL DEFAULT '',
  pool_id text NOT NULL DEFAULT '',
  website_url text NOT NULL DEFAULT '',
  tweet_url text NOT NULL DEFAULT '',
  metadata_uri text NOT NULL DEFAULT '',
  image_uri text NOT NULL DEFAULT '',
  launched_at timestamptz,
  deployer_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  fee_recipient_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  raw_payload_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  processing_stage text NOT NULL DEFAULT 'discovered',
  processing_error text,
  discovered_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS detect_accounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  launch_id uuid NOT NULL REFERENCES detect_launches(id) ON DELETE CASCADE,
  username text NOT NULL,
  username_lower text NOT NULL,
  identity_source text NOT NULL DEFAULT '',
  identity_confidence int NOT NULL DEFAULT 0,
  profile_url text NOT NULL DEFAULT '',
  display_name text NOT NULL DEFAULT '',
  description text NOT NULL DEFAULT '',
  followers int NOT NULL DEFAULT 0,
  following int NOT NULL DEFAULT 0,
  statuses int NOT NULL DEFAULT 0,
  website_url text NOT NULL DEFAULT '',
  avatar_url text NOT NULL DEFAULT '',
  banner_url text NOT NULL DEFAULT '',
  joined_raw text NOT NULL DEFAULT '',
  x_posts_collected int NOT NULL DEFAULT 0,
  x_posts_target int NOT NULL DEFAULT 50,
  x_fetch_meta_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  interaction_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  processing_stage text NOT NULL DEFAULT 'identity_resolved',
  processing_error text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(launch_id, username_lower)
);

CREATE TABLE IF NOT EXISTS detect_x_posts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL REFERENCES detect_accounts(id) ON DELETE CASCADE,
  tweet_id text NOT NULL UNIQUE,
  author_username text NOT NULL DEFAULT '',
  author_display_name text NOT NULL DEFAULT '',
  url text NOT NULL DEFAULT '',
  body_text text NOT NULL DEFAULT '',
  created_at_raw text NOT NULL DEFAULT '',
  created_timestamp bigint,
  reply_count int NOT NULL DEFAULT 0,
  repost_count int NOT NULL DEFAULT 0,
  like_count int NOT NULL DEFAULT 0,
  bookmark_count int NOT NULL DEFAULT 0,
  view_count int NOT NULL DEFAULT 0,
  media_urls_json jsonb NOT NULL DEFAULT '[]'::jsonb,
  raw_payload_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  inserted_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS detect_github_repos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL REFERENCES detect_accounts(id) ON DELETE CASCADE,
  canonical_url text NOT NULL,
  source text NOT NULL DEFAULT '',
  owner text NOT NULL DEFAULT '',
  repo text NOT NULL DEFAULT '',
  full_name text NOT NULL DEFAULT '',
  description text NOT NULL DEFAULT '',
  stars int NOT NULL DEFAULT 0,
  forks int NOT NULL DEFAULT 0,
  subscribers int NOT NULL DEFAULT 0,
  open_issues int NOT NULL DEFAULT 0,
  language text NOT NULL DEFAULT '',
  pushed_at text NOT NULL DEFAULT '',
  created_at_raw text NOT NULL DEFAULT '',
  license_spdx text NOT NULL DEFAULT '',
  topics_json jsonb NOT NULL DEFAULT '[]'::jsonb,
  languages_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  contributors_json jsonb NOT NULL DEFAULT '[]'::jsonb,
  releases_json jsonb NOT NULL DEFAULT '[]'::jsonb,
  score int NOT NULL DEFAULT 0,
  score_breakdown_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  raw_payload_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(account_id, canonical_url)
);

CREATE TABLE IF NOT EXISTS detect_account_assessments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL UNIQUE REFERENCES detect_accounts(id) ON DELETE CASCADE,
  archetype text NOT NULL DEFAULT 'unknown',
  verdict text NOT NULL DEFAULT 'unclear',
  summary text NOT NULL DEFAULT '',
  scores_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  reasons_json jsonb NOT NULL DEFAULT '[]'::jsonb,
  risks_json jsonb NOT NULL DEFAULT '[]'::jsonb,
  evidence_json jsonb NOT NULL DEFAULT '[]'::jsonb,
  model text NOT NULL DEFAULT '',
  raw_payload_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_detect_launches_stage ON detect_launches(processing_stage, discovered_at DESC);
CREATE INDEX IF NOT EXISTS idx_detect_launches_recent ON detect_launches(discovered_at DESC);
CREATE INDEX IF NOT EXISTS idx_detect_accounts_stage ON detect_accounts(processing_stage, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_detect_x_posts_account ON detect_x_posts(account_id, created_timestamp DESC NULLS LAST);
CREATE INDEX IF NOT EXISTS idx_detect_github_account ON detect_github_repos(account_id, score DESC);

CREATE OR REPLACE VIEW detect_dashboard AS
SELECT
  l.id AS launch_id,
  l.activity_id,
  l.token_name,
  l.token_symbol,
  l.chain,
  l.token_address,
  l.website_url AS launch_website_url,
  l.tweet_url,
  l.launched_at,
  l.discovered_at,
  l.processing_stage AS launch_stage,
  l.processing_error AS launch_error,
  a.id AS account_id,
  a.username,
  a.identity_source,
  a.identity_confidence,
  a.profile_url,
  a.display_name,
  a.description AS profile_description,
  a.followers,
  a.following,
  a.statuses,
  a.website_url AS profile_website_url,
  a.avatar_url,
  a.x_posts_collected,
  a.x_posts_target,
  a.interaction_json,
  a.processing_stage AS account_stage,
  a.processing_error AS account_error,
  ass.archetype,
  ass.verdict,
  ass.summary,
  ass.scores_json,
  ass.reasons_json,
  ass.risks_json,
  ass.evidence_json,
  ass.model,
  COALESCE(
    (
      SELECT jsonb_agg(
        jsonb_build_object(
          'canonical_url', gr.canonical_url,
          'source', gr.source,
          'full_name', gr.full_name,
          'description', gr.description,
          'stars', gr.stars,
          'forks', gr.forks,
          'language', gr.language,
          'pushed_at', gr.pushed_at,
          'license_spdx', gr.license_spdx,
          'score', gr.score,
          'score_breakdown', gr.score_breakdown_json
        )
        ORDER BY gr.score DESC, gr.created_at ASC
      )
      FROM detect_github_repos gr
      WHERE gr.account_id = a.id
    ),
    '[]'::jsonb
  ) AS github_repos_json,
  COALESCE(
    (
      SELECT jsonb_agg(
        jsonb_build_object(
          'tweet_id', xp.tweet_id,
          'url', xp.url,
          'text', xp.body_text,
          'created_at', xp.created_at_raw,
          'likes', xp.like_count,
          'reposts', xp.repost_count,
          'replies', xp.reply_count,
          'views', xp.view_count
        )
        ORDER BY xp.created_timestamp DESC NULLS LAST
      )
      FROM (
        SELECT *
        FROM detect_x_posts xpi
        WHERE xpi.account_id = a.id
        ORDER BY xpi.created_timestamp DESC NULLS LAST
        LIMIT 6
      ) xp
    ),
    '[]'::jsonb
  ) AS recent_posts_json
FROM detect_launches l
LEFT JOIN detect_accounts a ON a.launch_id = l.id
LEFT JOIN detect_account_assessments ass ON ass.account_id = a.id;

