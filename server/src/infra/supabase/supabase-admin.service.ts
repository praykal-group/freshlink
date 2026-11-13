import { HttpStatus, Injectable } from '@nestjs/common';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { AppError } from '../../common/errors/app-error';
import { AppConfig } from '../../config/config.service';

/** ~100 years: Supabase "ban" used to disable an account (Section 6.2). */
const BAN_FOREVER = '876000h';

/**
 * Thin wrapper over the Supabase Auth admin API (service role key, server only).
 * Identity only: no app data is ever written to Supabase (D-21).
 */
@Injectable()
export class SupabaseAdmin {
  private client?: SupabaseClient;

  constructor(private readonly config: AppConfig) {}

  private admin() {
    const key = this.config.get('SUPABASE_SERVICE_ROLE_KEY');
    if (!key) {
      throw new AppError('SUPABASE_NOT_CONFIGURED', 'SUPABASE_SERVICE_ROLE_KEY is not set', HttpStatus.SERVICE_UNAVAILABLE);
    }
    this.client ??= createClient(this.config.get('SUPABASE_URL'), key, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    return this.client.auth.admin;
  }

  private fail(op: string, message: string): never {
    throw new AppError('SUPABASE_ERROR', `Supabase ${op} failed: ${message}`, HttpStatus.BAD_GATEWAY);
  }

  /** Phone users are pre-confirmed; they log in with OTP. */
  async createPhoneUser(phone: string): Promise<string> {
    const { data, error } = await this.admin().createUser({ phone, phone_confirm: true });
    if (error || !data.user) this.fail('createUser', error?.message ?? 'no user');
    return data.user.id;
  }

  /** The invite mail verifies the address (AUTH-06). */
  async inviteEmail(email: string): Promise<string> {
    const redirectTo = `${this.config.get('APP_BASE_URL')}/console/`;
    const { data, error } = await this.admin().inviteUserByEmail(email, { redirectTo });
    if (error || !data.user) this.fail('inviteUserByEmail', error?.message ?? 'no user');
    return data.user.id;
  }

  async setBanned(uid: string, banned: boolean): Promise<void> {
    const { error } = await this.admin().updateUserById(uid, { ban_duration: banned ? BAN_FOREVER : 'none' });
    if (error) this.fail('updateUserById', error.message);
  }

  async emailConfirmedAt(uid: string): Promise<Date | null> {
    const { data, error } = await this.admin().getUserById(uid);
    if (error) this.fail('getUserById', error.message);
    return data.user?.email_confirmed_at ? new Date(data.user.email_confirmed_at) : null;
  }

  get configured(): boolean {
    return !!this.config.get('SUPABASE_SERVICE_ROLE_KEY');
  }
}
