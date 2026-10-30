// Tipos do banco. Escrito à mão a partir de supabase/migrations; quando o
// projeto estiver ligado, regenere com:
//   npx supabase gen types typescript --project-id ublmnybcognkqcnpqpnz > app/types/database.types.ts

export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[]

export type MemberRole = 'personal' | 'nutri' | 'aluno'
export type LinkStatus = 'ativo' | 'pausado' | 'encerrado'

export type Database = {
  public: {
    Tables: {
      profiles: {
        Row: {
          id: string
          full_name: string
          phone: string | null
          timezone: string
          created_at: string
          updated_at: string
        }
        Insert: never
        Update: {
          full_name?: string
          phone?: string | null
          timezone?: string
        }
        Relationships: []
      }
      organizations: {
        Row: {
          id: string
          name: string
          owner_id: string
          created_at: string
        }
        Insert: never
        Update: { name?: string }
        Relationships: []
      }
      memberships: {
        Row: {
          organization_id: string
          user_id: string
          role: MemberRole
          is_admin: boolean
          registry: string | null
          created_at: string
        }
        Insert: never
        Update: never
        Relationships: [
          {
            foreignKeyName: 'memberships_organization_id_fkey'
            columns: ['organization_id']
            isOneToOne: false
            referencedRelation: 'organizations'
            referencedColumns: ['id']
          },
          {
            foreignKeyName: 'memberships_user_id_fkey'
            columns: ['user_id']
            isOneToOne: false
            referencedRelation: 'profiles'
            referencedColumns: ['id']
          },
        ]
      }
      coach_students: {
        Row: {
          organization_id: string
          professional_id: string
          student_id: string
          status: LinkStatus
          since: string
        }
        Insert: never
        Update: { status?: LinkStatus }
        Relationships: [
          {
            foreignKeyName: 'coach_students_professional_id_fkey'
            columns: ['professional_id']
            isOneToOne: false
            referencedRelation: 'profiles'
            referencedColumns: ['id']
          },
          {
            foreignKeyName: 'coach_students_student_id_fkey'
            columns: ['student_id']
            isOneToOne: false
            referencedRelation: 'profiles'
            referencedColumns: ['id']
          },
        ]
      }
      invites: {
        Row: {
          id: string
          organization_id: string
          invited_by: string
          role: MemberRole
          name: string | null
          code: string
          expires_at: string
          accepted_by: string | null
          accepted_at: string | null
          created_at: string
        }
        Insert: {
          organization_id: string
          invited_by: string
          role: MemberRole
          name?: string | null
        }
        Update: never
        Relationships: []
      }
    }
    Views: { [_ in never]: never }
    Functions: {
      create_organization: {
        Args: { org_name: string; cref?: string | null }
        Returns: string
      }
      get_invite: {
        Args: { invite_code: string }
        Returns: {
          organization_name: string
          role: MemberRole
          invited_by_name: string
          name: string | null
          valid: boolean
        }[]
      }
      accept_invite: {
        Args: { invite_code: string; registry?: string | null }
        Returns: string
      }
      link_student: {
        Args: { org: string; professional: string; student: string }
        Returns: undefined
      }
    }
    Enums: {
      member_role: MemberRole
      link_status: LinkStatus
    }
    CompositeTypes: { [_ in never]: never }
  }
}
