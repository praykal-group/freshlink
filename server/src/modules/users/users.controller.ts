import { Body, Controller, Get, HttpCode, Param, ParseUUIDPipe, Patch, Post, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { Roles } from '../../common/auth/decorators';
import { CreateUserDto, ListUsersQuery, UpdateUserDto } from './dto/user.dto';
import { UsersService } from './users.service';

@ApiTags('admin/users')
@ApiBearerAuth()
@Roles('ADMIN')
@Controller('admin/users')
export class UsersController {
  constructor(private readonly users: UsersService) {}

  @Get()
  list(@Query() q: ListUsersQuery) {
    return this.users.list(q);
  }

  @Post()
  create(@Body() dto: CreateUserDto) {
    return this.users.create(dto);
  }

  @Patch(':id')
  update(@Param('id', ParseUUIDPipe) id: string, @Body() dto: UpdateUserDto) {
    return this.users.update(id, dto);
  }

  @Post(':id/disable')
  @HttpCode(200)
  disable(@Param('id', ParseUUIDPipe) id: string) {
    return this.users.setDisabled(id, true);
  }

  @Post(':id/enable')
  @HttpCode(200)
  enable(@Param('id', ParseUUIDPipe) id: string) {
    return this.users.setDisabled(id, false);
  }

  @Post(':id/resend-invite')
  @HttpCode(200)
  resendInvite(@Param('id', ParseUUIDPipe) id: string) {
    return this.users.resendInvite(id);
  }
}
