-- ============================================================
-- CLEAN UP DUPLICATE TECH MAPPINGS
-- Run this in Supabase SQL Editor
-- ============================================================

-- STEP 1: See what duplicates exist
SELECT tech_name, COUNT(*) as count, 
       string_agg(user_id::text, ', ') as user_ids
FROM public.tech_name_map
GROUP BY tech_name
HAVING COUNT(*) > 1;

-- STEP 2: See all current mappings
SELECT id, user_id, tech_name, is_active 
FROM public.tech_name_map 
ORDER BY tech_name;

-- STEP 3: Clean up - delete ALL duplicates, keep only the most recent one
-- This removes the mess and lets you start fresh

-- First, delete from tech_profiles (it may have duplicates too)
DELETE FROM public.tech_profiles;

-- Then delete all from tech_name_map
DELETE FROM public.tech_name_map;

-- STEP 4: Now verify it's empty
SELECT COUNT(*) as remaining_mappings FROM public.tech_name_map;
SELECT COUNT(*) as remaining_profiles FROM public.tech_profiles;

-- ============================================================
-- STEP 5: Add correct mappings (replace with your actual user IDs)
-- Get user IDs from: Supabase > Authentication > Users
-- ============================================================

-- Example: Replace the user_id with the actual UID from Supabase Auth
-- INSERT INTO public.tech_name_map (user_id, tech_name, is_active)
-- VALUES 
--   ('PASTE_ABDEL_USER_ID_HERE', 'Abdel', true),
--   ('PASTE_ADIL_USER_ID_HERE', 'Adil', true),
--   ('PASTE_CHADI_USER_ID_HERE', 'Chadi', true);

-- INSERT INTO public.tech_profiles (user_id, display_name, tech_code, is_active)
-- VALUES 
--   ('PASTE_ABDEL_USER_ID_HERE', 'Abdel', 'abdel', true),
--   ('PASTE_ADIL_USER_ID_HERE', 'Adil', 'adil', true),
--   ('PASTE_CHADI_USER_ID_HERE', 'Chadi', 'chadi', true);

-- STEP 6: Verify the new mappings
SELECT tm.user_id, tm.tech_name, tm.is_active, tp.display_name
FROM public.tech_name_map tm
LEFT JOIN public.tech_profiles tp ON tp.user_id = tm.user_id
ORDER BY tm.tech_name;
