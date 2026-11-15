import { Reflector } from '@nestjs/core';
import { ROLES } from '../../common/auth/decorators';
import { UsersController } from './users.controller';
import { UsersService } from './users.service';

// M13: the ADMIN user list behind the Users screen.
describe('UsersService.list', () => {
  const rows = Array.from({ length: 3 }, (_, i) => ({ id: `u${i}`, name: `User ${i}`, createdAt: new Date(`2026-11-1${i}T00:00:00Z`) }));

  it('filters by role, status and a name / phone / email search; pages by cursor', async () => {
    const prisma = { user: { findMany: jest.fn().mockResolvedValue(rows) } };
    const s = new UsersService(prisma as never, {} as never, {} as never);
    const page = await s.list({ role: 'DRIVER', status: 'ACTIVE', q: ' ravi ', limit: 2 });
    const arg = prisma.user.findMany.mock.calls[0][0];
    expect(arg.where.AND).toEqual(expect.arrayContaining([{ role: 'DRIVER' }, { status: 'ACTIVE' }, { OR: [{ name: { contains: 'ravi', mode: 'insensitive' } }, { phone: { contains: 'ravi' } }, { email: { contains: 'ravi', mode: 'insensitive' } }] }]));
    expect(arg.take).toBe(3);
    expect(arg.select).not.toHaveProperty('supabaseUid'); // identity link stays server-side
    expect(page.items).toHaveLength(2);
    expect(page.nextCursor).toBeTruthy();
  });

  it('is ADMIN only', () => {
    expect(new Reflector().get(ROLES, UsersController)).toEqual(['ADMIN']);
  });
});
