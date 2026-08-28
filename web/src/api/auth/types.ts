export interface AuthUser {
  id: number;
  name: string;
  email: string;
  verified: boolean;
  admin: boolean;
  tenant_id: number;
  created_at: number;
  updated_at: number;
  /** Effective RBAC codes from role bindings (e.g. admin, operator, shop:read). */
  permissions?: string[];
}

export interface LoginRequest {
  email: string;
  password: string;
}

export interface RegisterRequest {
  name: string;
  email: string;
  password: string;
}

export interface LoginResult {
  token: string;
  user: AuthUser;
}

export interface ForgotPasswordRequest {
  email: string;
}

export interface ResetPasswordRequest {
  user_id: number;
  token: string;
  new_password: string;
}

export interface VerifyEmailRequest {
  user_id: number;
  token: string;
}

export interface UpdateProfileRequest {
  name?: string;
  email?: string;
}

export interface ChangePasswordRequest {
  old_password: string;
  new_password: string;
}
