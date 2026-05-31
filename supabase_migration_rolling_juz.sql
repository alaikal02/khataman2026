-- A. Tambahkan tipe grup ke tabel public.groups
ALTER TABLE public.groups 
ADD COLUMN IF NOT EXISTS tipe_grup VARCHAR(20) DEFAULT 'INSIDENTAL' 
  CHECK (tipe_grup IN ('RUTIN', 'INSIDENTAL'));

-- B. Tambahkan prioritas jatah admin ke tabel public.group_members
ALTER TABLE public.group_members 
ADD COLUMN IF NOT EXISTS prioritas_jatah BOOLEAN DEFAULT FALSE NOT NULL;

-- C. Tambahkan kolom kontrol ke slot_khataman
ALTER TABLE public.slot_khataman 
ADD COLUMN IF NOT EXISTS progres_persen INTEGER DEFAULT 0 
  CHECK (progres_persen BETWEEN 0 AND 100);

ALTER TABLE public.slot_khataman 
ADD COLUMN IF NOT EXISTS approval_lepas_status VARCHAR(20) DEFAULT NULL 
  CHECK (approval_lepas_status IN ('PENDING', 'REJECTED'));

ALTER TABLE public.slot_khataman 
ADD COLUMN IF NOT EXISTS username_sebelumnya VARCHAR(100) DEFAULT NULL;

-- D. Kebijakan RLS (Row Level Security) untuk menghapus anggota grup oleh Pembuat/Admin grup
ALTER TABLE public.group_members ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow group creator to remove members" ON public.group_members;
CREATE POLICY "Allow group creator to remove members" ON public.group_members
FOR DELETE TO authenticated
USING (
  auth.uid() = user_id -- Anggota bisa keluar sendiri
  OR 
  EXISTS (
    SELECT 1 FROM public.groups 
    WHERE public.groups.id_group = public.group_members.group_id 
    AND public.groups.creator_id = auth.uid()
  )
);

-- E. Trigger untuk memperbarui username_sebelumnya secara otomatis ketika username anggota berubah
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
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_username_updated ON public.users;
CREATE TRIGGER on_username_updated
  AFTER UPDATE OF username ON public.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_update_username();
