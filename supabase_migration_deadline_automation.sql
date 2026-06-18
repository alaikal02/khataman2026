-- 1. Create table to hold scheduled deadline notifications
CREATE TABLE IF NOT EXISTS public.scheduled_notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    putaran_id UUID NOT NULL REFERENCES public.putaran_siklus(id_putaran) ON DELETE CASCADE,
    group_id UUID NOT NULL REFERENCES public.groups(id_group) ON DELETE CASCADE,
    scheduled_for TIMESTAMP WITH TIME ZONE NOT NULL,
    type VARCHAR(20) NOT NULL CHECK (type IN ('H7', 'H1')),
    is_sent BOOLEAN DEFAULT FALSE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Index for scheduled time search performance
CREATE INDEX IF NOT EXISTS idx_scheduled_notifications_lookup 
ON public.scheduled_notifications (is_sent, scheduled_for);

-- 2. Trigger function to queue notifications on putaran_siklus creation or deadline update
CREATE OR REPLACE FUNCTION public.schedule_deadline_reminders()
RETURNS TRIGGER AS $$
DECLARE
    v_duration INTERVAL;
    v_group_id UUID;
BEGIN
    -- Cancel (delete) any pending unsent notifications for this putaran first
    DELETE FROM public.scheduled_notifications 
    WHERE putaran_id = NEW.id_putaran AND is_sent = FALSE;

    -- Schedule only if the cycle is ACTIVE and target_deadline is set
    IF NEW.status_aktif_selesai = 'AKTIF' AND NEW.target_deadline IS NOT NULL THEN
        v_duration := NEW.target_deadline - NEW.created_at;
        v_group_id := NEW.group_id;

        -- If duration >= 14 days, schedule H-7 and H-1
        IF v_duration >= INTERVAL '14 days' THEN
            -- H-7 reminder
            IF NEW.target_deadline - INTERVAL '7 days' > timezone('utc'::text, now()) THEN
                INSERT INTO public.scheduled_notifications (putaran_id, group_id, scheduled_for, type)
                VALUES (NEW.id_putaran, v_group_id, NEW.target_deadline - INTERVAL '7 days', 'H7');
            END IF;
            
            -- H-1 reminder
            IF NEW.target_deadline - INTERVAL '1 day' > timezone('utc'::text, now()) THEN
                INSERT INTO public.scheduled_notifications (putaran_id, group_id, scheduled_for, type)
                VALUES (NEW.id_putaran, v_group_id, NEW.target_deadline - INTERVAL '1 day', 'H1');
            END IF;
        ELSE
            -- Duration < 14 days, schedule H-1 only
            IF NEW.target_deadline - INTERVAL '1 day' > timezone('utc'::text, now()) THEN
                INSERT INTO public.scheduled_notifications (putaran_id, group_id, scheduled_for, type)
                VALUES (NEW.id_putaran, v_group_id, NEW.target_deadline - INTERVAL '1 day', 'H1');
            END IF;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Bind trigger to putaran_siklus table
DROP TRIGGER IF EXISTS on_putaran_siklus_scheduled ON public.putaran_siklus;
CREATE TRIGGER on_putaran_siklus_scheduled
    AFTER INSERT OR UPDATE OF status_aktif_selesai, target_deadline ON public.putaran_siklus
    FOR EACH ROW
    EXECUTE FUNCTION public.schedule_deadline_reminders();

-- 3. Trigger function to cancel scheduled notifications when progress hits 100%
CREATE OR REPLACE FUNCTION public.check_group_progress_for_reminders()
RETURNS TRIGGER AS $$
DECLARE
    v_completed_count INTEGER;
BEGIN
    -- CRITICAL FIX 1: Filter query strictly by the specific cycle ID (putaran_id)
    SELECT COUNT(*) INTO v_completed_count
    FROM public.slot_khataman
    WHERE putaran_id = NEW.putaran_id AND status_checklist = TRUE;

    -- If 30 slots are completed (100% progress), delete unsent queued reminder notifications
    IF v_completed_count = 30 THEN
        DELETE FROM public.scheduled_notifications
        WHERE putaran_id = NEW.putaran_id AND is_sent = FALSE;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Bind trigger to slot_khataman table
DROP TRIGGER IF EXISTS on_slot_progress_check_reminders ON public.slot_khataman;
CREATE TRIGGER on_slot_progress_check_reminders
    AFTER UPDATE OF status_checklist ON public.slot_khataman
    FOR EACH ROW
    EXECUTE FUNCTION public.check_group_progress_for_reminders();

-- 4. Database function to process scheduled reminders (called by hourly pg_cron or Edge Function)
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
        -- Ensure cycle is still active
        IF EXISTS (
            SELECT 1 FROM public.putaran_siklus 
            WHERE id_putaran = r.putaran_id AND status_aktif_selesai = 'AKTIF'
        ) THEN
            -- Retrieve group name
            SELECT nama_grup INTO v_group_name FROM public.groups WHERE id_group = r.group_id;

            -- Calculate remaining slots (uncompleted)
            SELECT COUNT(*) INTO v_juz_left 
            FROM public.slot_khataman 
            WHERE putaran_id = r.putaran_id AND status_checklist = FALSE;

            -- Only send if progress is not 100%
            IF v_juz_left > 0 THEN
                -- Insert notification for all approved group members
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

        -- Mark as processed
        UPDATE public.scheduled_notifications SET is_sent = TRUE WHERE id = r.id;
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. Enable pg_cron and schedule hourly processing job
CREATE EXTENSION IF NOT EXISTS pg_cron;

SELECT cron.unschedule('process-deadline-reminders-job'); -- Safe unschedule if exists
SELECT cron.schedule(
    'process-deadline-reminders-job',
    '0 * * * *', -- Every hour
    $$SELECT public.process_scheduled_deadline_reminders()$$
);
