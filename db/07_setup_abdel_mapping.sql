-- ============================================================
-- SETUP TECH MAPPING FOR a.hannoune@aigleinfo.ca
-- This allows Abdel to see his assigned jobs
-- Paste in Supabase SQL Editor and run
-- ============================================================

-- STEP 1: Find the user_id for a.hannoune@aigleinfo.ca
-- Run this and copy the user_id
SELECT id AS user_id, email FROM auth.users 
WHERE email ILIKE '%a.hannoune%';

-- STEP 2: Create the mapping
-- Replace 'PASTE_USER_ID_HERE' with the user_id from step 1

-- First check what columns exist in tech_profiles
SELECT column_name, data_type FROM information_schema.columns 
WHERE table_schema = 'public' AND table_name = 'tech_profiles';

-- Check what columns exist in tech_name_map  
SELECT column_name, data_type FROM information_schema.columns 
WHERE table_schema = 'public' AND table_name = 'tech_name_map';

-- STEP 3: Insert the mapping
-- NOTE: Only run the INSERT that matches your table structure

-- If tech_profiles has (user_id, display_name, tech_code, is_active):
INSERT INTO public.tech_profiles (user_id, display_name, tech_code, is_active)
SELECT id, 'Abdel', 'abdel', true
FROM auth.users 
WHERE email ILIKE '%a.hannoune@aigleinfo.ca';

-- If tech_name_map has (user_id, tech_name, is_active):
INSERT INTO public.tech_name_map (user_id, tech_name, is_active)
SELECT id, 'Abdel', true
FROM auth.users 
WHERE email ILIKE '%a.hannoune@aigleinfo.ca';

-- STEP 4: Verify
SELECT 'tech_profiles' AS tbl, user_id, display_name, tech_code, is_active
FROM public.tech_profiles
WHERE display_name = 'Abdel'
UNION ALL
SELECT 'tech_name_map' AS tbl, user_id, tech_name, NULL, is_active
FROM public.tech_name_map
WHERE tech_name = 'Abdel';

-- STEP 5: After this, the admin needs to:
-- 1. Log into the Dispatch Calendar
-- 2. Click "Generate plan" 
-- 3. Click "Apply scenario"
-- 4. Abdel logs out and logs back in
-- 5. Abdel should now see his assigned jobs
