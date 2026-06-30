-- ====================================================================
-- SUPABASE SECURITY PATCH
-- Project: Khataman Quran
-- ====================================================================

-- 1. Pastikan Row Level Security (RLS) Aktif di Semua Tabel Utama
ALTER TABLE IF EXISTS public.groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.group_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.slot_khataman ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.khataman_mandiri ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.riwayat_personal ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.putaran_siklus ENABLE ROW LEVEL SECURITY;

-- 2. Perbaiki Kebijakan SELECT pada public.group_members
-- Drop kebijakan SELECT yang terlalu longgar jika ada (mencegah akses baca anonim)
DROP POLICY IF EXISTS "Enable read access for all users" ON public.group_members;
DROP POLICY IF EXISTS "Allow select for all" ON public.group_members;
DROP POLICY IF EXISTS "Enable read access for all" ON public.group_members;
DROP POLICY IF EXISTS "Allow read for all users" ON public.group_members;
DROP POLICY IF EXISTS "group_members_select_policy" ON public.group_members;

-- Buat kebijakan baru yang hanya mengizinkan pengguna terautentikasi (authenticated) untuk melihat anggota grup
CREATE POLICY "Allow select for authenticated users" 
ON public.group_members 
FOR SELECT 
TO authenticated 
USING (true);

-- 3. Amankan Fungsi SECURITY DEFINER dengan Menetapkan search_path = public

-- A. Fungsi: handle_update_username
CREATE OR REPLACE FUNCTION public.handle_update_username()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.username IS DISTINCT FROM OLD.username THEN
    UPDATE public.slot_khataman
    SET username_sebelumnya = NEW.username
    WHERE username_sebelumnya = OLD.username;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- B. Fungsi: schedule_deadline_reminders
CREATE OR REPLACE FUNCTION public.schedule_deadline_reminders()
RETURNS TRIGGER AS $$
DECLARE
    v_duration INTERVAL;
    v_group_id UUID;
BEGIN
    -- Hapus notifikasi pengingat yang belum terkirim untuk putaran ini terlebih dahulu
    DELETE FROM public.scheduled_notifications 
    WHERE putaran_id = NEW.id_putaran AND is_sent = FALSE;

    -- Jadwalkan pengingat hanya jika siklus AKTIF dan target_deadline terisi
    IF NEW.status_aktif_selesai = 'AKTIF' AND NEW.target_deadline IS NOT NULL THEN
        v_duration := NEW.target_deadline - NEW.created_at;
        v_group_id := NEW.group_id;

        -- Jika durasi >= 14 hari, jadwalkan pengingat H-7 dan H-1
        IF v_duration >= INTERVAL '14 days' THEN
            -- Pengingat H-7
            IF NEW.target_deadline - INTERVAL '7 days' > timezone('utc'::text, now()) THEN
                INSERT INTO public.scheduled_notifications (putaran_id, group_id, scheduled_for, type)
                VALUES (NEW.id_putaran, v_group_id, NEW.target_deadline - INTERVAL '7 days', 'H7');
            END IF;
            
            -- Pengingat H-1
            IF NEW.target_deadline - INTERVAL '1 day' > timezone('utc'::text, now()) THEN
                INSERT INTO public.scheduled_notifications (putaran_id, group_id, scheduled_for, type)
                VALUES (NEW.id_putaran, v_group_id, NEW.target_deadline - INTERVAL '1 day', 'H1');
            END IF;
        ELSE
            -- Durasi < 14 hari, hanya jadwalkan pengingat H-1
            IF NEW.target_deadline - INTERVAL '1 day' > timezone('utc'::text, now()) THEN
                INSERT INTO public.scheduled_notifications (putaran_id, group_id, scheduled_for, type)
                VALUES (NEW.id_putaran, v_group_id, NEW.target_deadline - INTERVAL '1 day', 'H1');
            END IF;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- C. Fungsi: check_group_progress_for_reminders
CREATE OR REPLACE FUNCTION public.check_group_progress_for_reminders()
RETURNS TRIGGER AS $$
DECLARE
    v_completed_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_completed_count
    FROM public.slot_khataman
    WHERE putaran_id = NEW.putaran_id AND status_checklist = TRUE;

    -- Jika seluruh 30 juz selesai (progres 100%), batalkan pengingat yang tersisa
    IF v_completed_count = 30 THEN
        DELETE FROM public.scheduled_notifications
        WHERE putaran_id = NEW.putaran_id AND is_sent = FALSE;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- D. Fungsi: process_scheduled_deadline_reminders
CREATE OR REPLACE FUNCTION public.process_scheduled_deadline_reminders()
RETURNS VOID AS $$
DECLARE
    r RECORD;
    v_member RECORD;
    v_juz_left INTEGER;
    v_group_name VARCHAR;
BEGIN
    FOR r IN 
        SELECT id, putaran_id, group_id, type 
        FROM public.scheduled_notifications 
        WHERE scheduled_for <= timezone('utc'::text, now()) AND is_sent = FALSE
    LOOP
        -- Pastikan putaran siklus masih aktif
        IF EXISTS (
            SELECT 1 FROM public.putaran_siklus 
            WHERE id_putaran = r.putaran_id AND status_aktif_selesai = 'AKTIF'
        ) THEN
            SELECT nama_grup INTO v_group_name FROM public.groups WHERE id_group = r.group_id;

            SELECT COUNT(*) INTO v_juz_left 
            FROM public.slot_khataman 
            WHERE putaran_id = r.putaran_id AND status_checklist = FALSE;

            IF v_juz_left > 0 THEN
                -- Kirim notifikasi ke semua anggota yang berstatus APPROVED
                FOR v_member IN 
                    SELECT user_id FROM public.group_members 
                    WHERE group_id = r.group_id AND approval_status = 'APPROVED'
                LOOP
                    INSERT INTO public.notifications (user_id, type, title, body, group_id)
                    VALUES (
                        v_member.user_id,
                        'DEADLINE_REMINDER',
                        'Pengingat Tenggat Waktu ⏳',
                        CASE 
                            WHEN r.type = 'H7' THEN 'Grup "' || v_group_name || '" memiliki sisa ' || v_juz_left || ' Juz lagi. Batas waktu tinggal 7 hari lagi!'
                            ELSE 'Ayo selesaikan! Grup "' || v_group_name || '" memiliki sisa ' || v_juz_left || ' Juz lagi. Batas waktu tinggal 24 jam lagi!'
                        END,
                        r.group_id
                    );
                END LOOP;
            END IF;
        END IF;

        UPDATE public.scheduled_notifications SET is_sent = TRUE WHERE id = r.id;
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;
