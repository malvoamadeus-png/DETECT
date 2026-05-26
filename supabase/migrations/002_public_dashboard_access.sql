GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT SELECT ON detect_dashboard TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
