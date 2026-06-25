import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  print('Initializing Supabase...');
  final supabase = SupabaseClient(
    'https://vlvuxcunpgjoqavwkvjs.supabase.co',
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZsdnV4Y3VucGdqb3FhdndrdmpzIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3ODA3Mzg5OSwiZXhwIjoyMDkzNjQ5ODk5fQ.DIif4N_9JK-JZbGzzioE45gPwZyX-TLKEWk1y0IPp9g',
  );

  final userId = '9bceb956-c3f3-449f-b6ef-595c8512acf8';
  print('Fetching khataman_mandiri for user $userId...');
  try {
    final mandiriData = await supabase
        .from('khataman_mandiri')
        .select('*')
        .eq('user_id', userId);
    print('Khataman Mandiri count: ${mandiriData.length}');
    for (var row in mandiriData) {
      print('Row: $row');
    }
  } catch (e) {
    print('Failed with: $e');
  }
}
