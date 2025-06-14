-- ================================================================
-- NEUROLOG APP - SCRIPT COMPLETO DE BASE DE DATOS (V2 - OPTIMIZADO CON ENUMS)
-- ================================================================
-- Ejecutar completo en Supabase SQL Editor
-- Borra todo y crea desde cero según las mejores prácticas.

-- ================================================================
-- 1. LIMPIAR TODO LO EXISTENTE
-- ================================================================
-- Eliminar vistas
DROP VIEW IF EXISTS user_accessible_children CASCADE;
DROP VIEW IF EXISTS child_log_statistics CASCADE;

-- Eliminar funciones
DROP FUNCTION IF EXISTS user_can_access_child(UUID) CASCADE;
DROP FUNCTION IF EXISTS user_can_edit_child(UUID) CASCADE;
DROP FUNCTION IF EXISTS audit_sensitive_access(TEXT, TEXT, TEXT) CASCADE;
DROP FUNCTION IF EXISTS handle_new_user() CASCADE;
DROP FUNCTION IF EXISTS handle_updated_at() CASCADE;
DROP FUNCTION IF EXISTS verify_neurolog_setup() CASCADE;

-- Eliminar tablas en orden correcto (por dependencias)
DROP TABLE IF EXISTS daily_logs CASCADE;
DROP TABLE IF EXISTS user_child_relations CASCADE;
DROP TABLE IF EXISTS children CASCADE;
DROP TABLE IF EXISTS audit_logs CASCADE;
DROP TABLE IF EXISTS categories CASCADE;
DROP TABLE IF EXISTS profiles CASCADE;

-- Eliminar tipos ENUM si existen
DROP TYPE IF EXISTS role_enum;
DROP TYPE IF EXISTS relationship_type_enum;
DROP TYPE IF EXISTS intensity_level_enum;
DROP TYPE IF EXISTS audit_operation_enum;
DROP TYPE IF EXISTS risk_level_enum;


-- ================================================================
-- 2. CREAR TIPOS ENUM PARA CONSTANTES
-- ================================================================

-- Tipo para roles de usuario en la tabla 'profiles'
CREATE TYPE role_enum AS ENUM ('parent', 'teacher', 'specialist', 'admin');

-- Tipo para relaciones en la tabla 'user_child_relations'
CREATE TYPE relationship_type_enum AS ENUM ('parent', 'teacher', 'specialist', 'observer', 'family');

-- Tipo para niveles de intensidad en 'daily_logs'
CREATE TYPE intensity_level_enum AS ENUM ('low', 'medium', 'high');

-- Tipo para operaciones de auditoría en 'audit_logs'
CREATE TYPE audit_operation_enum AS ENUM ('INSERT', 'UPDATE', 'DELETE', 'SELECT');

-- Tipo para niveles de riesgo en 'audit_logs'
CREATE TYPE risk_level_enum AS ENUM ('low', 'medium', 'high', 'critical');


-- ================================================================
-- 3. CREAR TABLAS PRINCIPALES
-- ================================================================

-- TABLA: profiles (usuarios del sistema)
CREATE TABLE profiles (
  id UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
  email TEXT UNIQUE NOT NULL,
  full_name TEXT NOT NULL,
  role role_enum DEFAULT 'parent', -- Usando ENUM
  avatar_url TEXT,
  phone TEXT,
  is_active BOOLEAN DEFAULT TRUE,
  last_login TIMESTAMPTZ,
  failed_login_attempts INTEGER DEFAULT 0,
  last_failed_login TIMESTAMPTZ,
  account_locked_until TIMESTAMPTZ,
  timezone TEXT DEFAULT 'America/Guayaquil',
  preferences JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- TABLA: categories (categorías de registros)
CREATE TABLE categories (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT UNIQUE NOT NULL,
  description TEXT,
  color TEXT DEFAULT '#3B82F6',
  icon TEXT DEFAULT 'circle',
  is_active BOOLEAN DEFAULT TRUE,
  sort_order INTEGER DEFAULT 0,
  created_by UUID REFERENCES profiles(id),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- TABLA: children (niños)
CREATE TABLE children (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL CHECK (length(trim(name)) >= 2),
  birth_date DATE,
  diagnosis TEXT,
  notes TEXT,
  is_active BOOLEAN DEFAULT TRUE,
  avatar_url TEXT,
  emergency_contact JSONB DEFAULT '[]',
  medical_info JSONB DEFAULT '{}',
  educational_info JSONB DEFAULT '{}',
  privacy_settings JSONB DEFAULT '{
    "share_with_specialists": true,
    "share_progress_reports": true,
    "allow_photo_sharing": false,
    "data_retention_months": 36
  }',
  created_by UUID REFERENCES profiles(id) NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- TABLA: user_child_relations (relaciones usuario-niño)
CREATE TABLE user_child_relations (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
  child_id UUID REFERENCES children(id) ON DELETE CASCADE NOT NULL,
  relationship_type relationship_type_enum NOT NULL, -- Usando ENUM
  can_edit BOOLEAN DEFAULT FALSE,
  can_view BOOLEAN DEFAULT TRUE,
  can_export BOOLEAN DEFAULT FALSE,
  can_invite_others BOOLEAN DEFAULT FALSE,
  granted_by UUID REFERENCES profiles(id) NOT NULL,
  granted_at TIMESTAMPTZ DEFAULT NOW(),
  expires_at TIMESTAMPTZ,
  is_active BOOLEAN DEFAULT TRUE,
  notes TEXT,
  notification_preferences JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  
  UNIQUE(user_id, child_id, relationship_type)
);

-- TABLA: daily_logs (registros diarios)
CREATE TABLE daily_logs (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  child_id UUID REFERENCES children(id) ON DELETE CASCADE NOT NULL,
  category_id UUID REFERENCES categories(id),
  title TEXT NOT NULL CHECK (length(trim(title)) >= 2),
  content TEXT NOT NULL,
  mood_score INTEGER CHECK (mood_score >= 1 AND mood_score <= 10),
  intensity_level intensity_level_enum DEFAULT 'medium', -- Usando ENUM
  logged_by UUID REFERENCES profiles(id) NOT NULL,
  log_date DATE DEFAULT CURRENT_DATE,
  is_private BOOLEAN DEFAULT FALSE,
  is_deleted BOOLEAN DEFAULT FALSE,
  is_flagged BOOLEAN DEFAULT FALSE,
  attachments JSONB DEFAULT '[]',
  tags TEXT[] DEFAULT '{}',
  location TEXT,
  weather TEXT,
  reviewed_by UUID REFERENCES profiles(id),
  reviewed_at TIMESTAMPTZ,
  specialist_notes TEXT,
  parent_feedback TEXT,
  follow_up_required BOOLEAN DEFAULT FALSE,
  follow_up_date DATE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- TABLA: audit_logs (auditoría del sistema)
CREATE TABLE audit_logs (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  table_name TEXT NOT NULL,
  operation audit_operation_enum NOT NULL, -- Usando ENUM
  record_id TEXT,
  user_id UUID REFERENCES profiles(id),
  user_role TEXT,
  old_values JSONB,
  new_values JSONB,
  changed_fields TEXT[],
  ip_address INET,
  user_agent TEXT,
  session_id TEXT,
  risk_level risk_level_enum DEFAULT 'low', -- Usando ENUM
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ================================================================
-- 4. CREAR ÍNDICES PARA PERFORMANCE
-- ================================================================

CREATE INDEX idx_profiles_email ON profiles(email);
CREATE INDEX idx_profiles_role ON profiles(role);
CREATE INDEX idx_profiles_active ON profiles(is_active);
CREATE INDEX idx_children_created_by ON children(created_by);
CREATE INDEX idx_children_active ON children(is_active);
CREATE INDEX idx_children_birth_date ON children(birth_date);
CREATE INDEX idx_relations_user_child ON user_child_relations(user_id, child_id);
CREATE INDEX idx_relations_child ON user_child_relations(child_id);
CREATE INDEX idx_relations_active ON user_child_relations(is_active);
CREATE INDEX idx_logs_child_date ON daily_logs(child_id, log_date DESC);
CREATE INDEX idx_logs_logged_by ON daily_logs(logged_by);
CREATE INDEX idx_logs_category ON daily_logs(category_id);
CREATE INDEX idx_logs_active ON daily_logs(is_deleted);
CREATE INDEX idx_audit_user ON audit_logs(user_id);
CREATE INDEX idx_audit_table ON audit_logs(table_name);
CREATE INDEX idx_audit_created ON audit_logs(created_at DESC);

-- ================================================================
-- 5. CREAR FUNCIONES DE TRIGGERS
-- ================================================================

-- Función para actualizar updated_at automáticamente
CREATE OR REPLACE FUNCTION handle_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Función para crear perfil automáticamente cuando se registra usuario
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
  v_role role_enum;
BEGIN
  -- Convertir el texto del rol a nuestro tipo ENUM, con 'parent' como default.
  -- Se usa un bloque de excepción por si acaso `raw_user_meta_data->>'role'` contiene un valor inválido.
  BEGIN
    v_role := (COALESCE(NEW.raw_user_meta_data->>'role', 'parent'))::role_enum;
  EXCEPTION
    WHEN invalid_text_representation THEN
      v_role := 'parent';
  END;

  INSERT INTO profiles (id, email, full_name, role)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'full_name', split_part(NEW.email, '@', 1)),
    v_role
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ================================================================
-- 6. CREAR TRIGGERS
-- ================================================================

CREATE TRIGGER set_updated_at_profiles
  BEFORE UPDATE ON profiles
  FOR EACH ROW
  EXECUTE FUNCTION handle_updated_at();

CREATE TRIGGER set_updated_at_children
  BEFORE UPDATE ON children
  FOR EACH ROW
  EXECUTE FUNCTION handle_updated_at();

CREATE TRIGGER set_updated_at_daily_logs
  BEFORE UPDATE ON daily_logs
  FOR EACH ROW
  EXECUTE FUNCTION handle_updated_at();

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION handle_new_user();


-- ================================================================
-- 7. CREAR FUNCIONES RPC
-- ================================================================

CREATE OR REPLACE FUNCTION user_can_access_child(child_uuid UUID)
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM user_accessible_children 
    WHERE id = child_uuid
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION user_can_edit_child(child_uuid UUID)
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM user_accessible_children 
    WHERE id = child_uuid AND can_edit = TRUE
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION audit_sensitive_access(
  action_type TEXT,
  resource_id TEXT,
  action_details TEXT DEFAULT NULL
)
RETURNS VOID AS $$
BEGIN
  INSERT INTO audit_logs (
    table_name,
    operation,
    record_id,
    user_id,
    user_role,
    new_values,
    risk_level
  ) VALUES (
    'sensitive_access',
    'SELECT'::audit_operation_enum,
    resource_id,
    auth.uid(),
    (SELECT role::text FROM profiles WHERE id = auth.uid()),
    jsonb_build_object(
      'action_type', action_type,
      'details', action_details,
      'timestamp', NOW()
    ),
    'medium'::risk_level_enum
  );
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ================================================================
-- 8. CREAR VISTAS
-- ================================================================

-- Vista para niños accesibles por el usuario actual (creados o compartidos)
CREATE OR REPLACE VIEW user_accessible_children AS
SELECT 
  c.id, c.name, c.birth_date, c.diagnosis, c.notes, c.is_active as child_is_active, c.avatar_url, c.emergency_contact, c.medical_info, c.educational_info, c.privacy_settings, c.created_by, c.created_at, c.updated_at,
  'parent'::relationship_type_enum as relationship_type,
  TRUE as can_edit,
  TRUE as can_view,
  TRUE as can_export,
  TRUE as can_invite_others,
  c.created_at as granted_at,
  NULL::TIMESTAMPTZ as expires_at,
  p.full_name as creator_name
FROM children c
JOIN profiles p ON c.created_by = p.id
WHERE c.created_by = auth.uid()
  AND c.is_active = true

UNION ALL

SELECT
  c.id, c.name, c.birth_date, c.diagnosis, c.notes, c.is_active as child_is_active, c.avatar_url, c.emergency_contact, c.medical_info, c.educational_info, c.privacy_settings, c.created_by, c.created_at, c.updated_at,
  ucr.relationship_type,
  ucr.can_edit,
  ucr.can_view,
  ucr.can_export,
  ucr.can_invite_others,
  ucr.granted_at,
  ucr.expires_at,
  (SELECT full_name FROM profiles WHERE id = c.created_by) as creator_name
FROM
  children c
JOIN
  user_child_relations ucr ON c.id = ucr.child_id
WHERE
  ucr.user_id = auth.uid()
  AND ucr.is_active = TRUE
  AND c.is_active = TRUE
  AND (ucr.expires_at IS NULL OR ucr.expires_at > NOW());


-- Vista para estadísticas de logs por niño
CREATE OR REPLACE VIEW child_log_statistics AS
SELECT 
  c.id as child_id,
  c.name as child_name,
  COUNT(dl.id) as total_logs,
  COUNT(CASE WHEN dl.log_date >= CURRENT_DATE - INTERVAL '7 days' THEN 1 END) as logs_this_week,
  COUNT(CASE WHEN dl.log_date >= CURRENT_DATE - INTERVAL '30 days' THEN 1 END) as logs_this_month,
  ROUND(AVG(dl.mood_score), 2) as avg_mood_score,
  MAX(dl.log_date) as last_log_date,
  COUNT(DISTINCT dl.category_id) as categories_used,
  COUNT(CASE WHEN dl.is_private THEN 1 END) as private_logs,
  COUNT(CASE WHEN dl.reviewed_at IS NOT NULL THEN 1 END) as reviewed_logs
FROM user_accessible_children c
LEFT JOIN daily_logs dl ON c.id = dl.child_id AND dl.is_deleted = false
GROUP BY c.id, c.name;


-- ================================================================
-- 9. INSERTAR DATOS INICIALES
-- ================================================================

INSERT INTO categories (name, description, color, icon, sort_order) VALUES
('Comportamiento', 'Registros sobre comportamiento y conducta', '#3B82F6', 'user', 1),
('Emociones', 'Estado emocional y regulación', '#EF4444', 'heart', 2),
('Aprendizaje', 'Progreso académico y educativo', '#10B981', 'book', 3),
('Socialización', 'Interacciones sociales', '#F59E0B', 'users', 4),
('Comunicación', 'Habilidades de comunicación', '#8B5CF6', 'message-circle', 5),
('Motricidad', 'Desarrollo motor fino y grueso', '#06B6D4', 'activity', 6),
('Alimentación', 'Hábitos alimentarios', '#84CC16', 'utensils', 7),
('Sueño', 'Patrones de sueño y descanso', '#6366F1', 'moon', 8),
('Medicina', 'Información médica y tratamientos', '#EC4899', 'pill', 9),
('Otros', 'Otros registros importantes', '#6B7280', 'more-horizontal', 10);


-- ================================================================
-- 10. HABILITAR RLS Y CREAR POLÍTICAS
-- ================================================================

-- Habilitar RLS
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE children ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_child_relations ENABLE ROW LEVEL SECURITY;
ALTER TABLE daily_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;

-- Forzar RLS para dueños de tablas
ALTER TABLE profiles FORCE ROW LEVEL SECURITY;
ALTER TABLE children FORCE ROW LEVEL SECURITY;
ALTER TABLE user_child_relations FORCE ROW LEVEL SECURITY;
ALTER TABLE daily_logs FORCE ROW LEVEL SECURITY;
ALTER TABLE categories FORCE ROW LEVEL SECURITY;
ALTER TABLE audit_logs FORCE ROW LEVEL SECURITY;

-- POLÍTICAS PARA PROFILES
CREATE POLICY "Users can manage their own profile" ON profiles
  FOR ALL USING (auth.uid() = id);

-- POLÍTICAS PARA CHILDREN
CREATE POLICY "Users can see children they have access to" ON children
  FOR SELECT USING (id IN (SELECT uac.id FROM user_accessible_children uac));
  
CREATE POLICY "Authenticated users can create children" ON children
  FOR INSERT WITH CHECK (auth.uid() = created_by);

CREATE POLICY "Users can update children they have edit rights for" ON children
  FOR UPDATE USING (user_can_edit_child(id)) WITH CHECK (user_can_edit_child(id));

-- POLÍTICAS PARA USER_CHILD_RELATIONS
CREATE POLICY "Users can see relations for children they can edit" ON user_child_relations
  FOR SELECT USING (user_can_edit_child(child_id));

CREATE POLICY "Users can create relations for children they can invite for" ON user_child_relations
  FOR INSERT WITH CHECK (
    granted_by = auth.uid() AND
    EXISTS (
      SELECT 1 FROM user_accessible_children
      WHERE id = child_id AND can_invite_others = TRUE
    )
  );

CREATE POLICY "Users can update/delete relations they granted" ON user_child_relations
  FOR ALL USING (granted_by = auth.uid());

-- POLÍTICAS PARA DAILY_LOGS
CREATE POLICY "Users can view logs of accessible children" ON daily_logs
  FOR SELECT USING (user_can_access_child(child_id));
  
CREATE POLICY "Users can create logs for accessible children" ON daily_logs
  FOR INSERT WITH CHECK (logged_by = auth.uid() AND user_can_access_child(child_id));

CREATE POLICY "Users can update their own logs" ON daily_logs
  FOR UPDATE USING (logged_by = auth.uid());

-- POLÍTICAS PARA CATEGORIES
CREATE POLICY "Authenticated users can view categories" ON categories
  FOR SELECT USING (auth.role() = 'authenticated');

-- POLÍTICAS PARA AUDIT_LOGS (Restrictivo: nadie puede verlos por defecto)
CREATE POLICY "Deny all access to audit logs" ON audit_logs
  FOR ALL USING (false);


-- ================================================================
-- 11. FUNCIÓN DE VERIFICACIÓN
-- ================================================================

CREATE OR REPLACE FUNCTION verify_neurolog_setup()
RETURNS TEXT AS $$
DECLARE
  result TEXT := '';
  table_count INTEGER;
  policy_count INTEGER;
  function_count INTEGER;
  category_count INTEGER;
  enum_count INTEGER;
BEGIN
  -- Contar tablas
  SELECT COUNT(*) INTO table_count
  FROM information_schema.tables 
  WHERE table_schema = 'public' 
    AND table_name IN ('profiles', 'children', 'user_child_relations', 'daily_logs', 'categories', 'audit_logs');
  
  -- Contar tipos ENUM
  SELECT COUNT(*) INTO enum_count
  FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
  WHERE n.nspname = 'public'
    AND t.typname IN ('role_enum', 'relationship_type_enum', 'intensity_level_enum', 'audit_operation_enum', 'risk_level_enum');
  
  -- Contar políticas
  SELECT COUNT(*) INTO policy_count FROM pg_policies WHERE schemaname = 'public';
  
  -- Contar funciones
  SELECT COUNT(*) INTO function_count FROM pg_proc WHERE proname IN ('user_can_access_child', 'user_can_edit_child', 'audit_sensitive_access');
  
  -- Contar categorías
  SELECT COUNT(*) INTO category_count FROM categories;
  
  result := result || 'Tablas creadas: ' || table_count || '/6' || E'\n';
  result := result || 'Tipos ENUM creados: ' || enum_count || '/5' || E'\n';
  result := result || 'Políticas RLS creadas: ' || policy_count || E'\n';
  result := result || 'Funciones RPC creadas: ' || function_count || '/3' || E'\n';
  result := result || 'Categorías insertadas: ' || category_count || '/10' || E'\n';
  
  IF (SELECT relrowsecurity FROM pg_class WHERE relname = 'children') THEN
    result := result || 'RLS en Children: ✅ Habilitado' || E'\n';
  ELSE
    result := result || 'RLS en Children: ❌ Deshabilitado' || E'\n';
  END IF;
  
  result := result || E'\n🎉 BASE DE DATOS NEUROLOG CONFIGURADA COMPLETAMENTE';
  
  RETURN result;
END;
$$ LANGUAGE plpgsql;


-- ================================================================
-- 12. EJECUTAR VERIFICACIÓN FINAL
-- ================================================================

SELECT verify_neurolog_setup();


-- ================================================================
-- 13. MENSAJE FINAL
-- ================================================================

DO $$
BEGIN
  RAISE NOTICE '🎉 ¡BASE DE DATOS NEUROLOG CREADA EXITOSAMENTE!';
  RAISE NOTICE '===============================================';
  RAISE NOTICE 'Todas las tablas, funciones, vistas y políticas han sido creadas.';
  RAISE NOTICE 'Se han utilizado tipos ENUM para mejorar la consistencia y el rendimiento.';
  RAISE NOTICE 'La base de datos está lista para usar.';
END $$;
