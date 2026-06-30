-- ====================================================================
-- SUPABASE SECURITY PATCH (V2)
-- Project: Khataman Quran
-- ====================================================================

-- 1. Jalankan Blok PL/pgSQL untuk Menghapus Semua Kebijakan SELECT/ALL Lama pada group_members
DO $$
DECLARE
    pol RECORD;
BEGIN
    FOR pol IN 
        SELECT policyname 
        FROM pg_policies 
        WHERE schemaname = 'public' 
          AND tablename = 'group_members' 
          AND cmd IN ('SELECT', 'ALL')
    LOOP
        EXECUTE format('DROP POLICY %I ON public.group_members', pol.policyname);
    END LOOP;
END $$;

-- 2. Buat Kebijakan Baru yang Hanya Mengizinkan Pengguna Terautentikasi (authenticated)
CREATE POLICY "Allow select for authenticated users" 
ON public.group_members 
FOR SELECT 
TO authenticated 
USING (true);
