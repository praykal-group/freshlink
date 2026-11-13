import { Body, Controller, Get, Headers, HttpCode, Param, ParseUUIDPipe, Patch, Post, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import type { AuthUser } from '../../common/auth/auth-user';
import { CurrentUser, Roles } from '../../common/auth/decorators';
import { BatchesService } from './batches.service';
import {
  AssignStorageDto,
  AttachImageDto,
  AttachTagDto,
  CreateBatchDto,
  EditableBatchFieldsDto,
  EditRequestDto,
  ListBatchesQuery,
  ListEditRequestsQuery,
  ReceiveDto,
  ReviewDto,
} from './dto/batch.dto';

const Id = () => Param('id', ParseUUIDPipe);

/** Operators work on their site's batches; managers read all and approve edits (Section 6.3). */
@ApiTags('batches')
@ApiBearerAuth()
@Roles('OPERATOR', 'MANAGER', 'ADMIN')
@Controller()
export class BatchesController {
  constructor(private readonly batches: BatchesService) {}

  @Post('batches')
  @Roles('OPERATOR', 'ADMIN')
  create(@CurrentUser() user: AuthUser, @Body() dto: CreateBatchDto, @Headers('x-device-id') deviceId?: string) {
    return this.batches.create(user, dto, deviceId);
  }

  @Get('batches')
  list(@CurrentUser() user: AuthUser, @Query() q: ListBatchesQuery) {
    return this.batches.list(user, q);
  }

  @Get('batches/:id')
  get(@CurrentUser() user: AuthUser, @Id() id: string) {
    return this.batches.get(user, id);
  }

  @Patch('batches/:id')
  @Roles('OPERATOR', 'ADMIN')
  update(@CurrentUser() user: AuthUser, @Id() id: string, @Body() dto: EditableBatchFieldsDto) {
    return this.batches.update(user, id, dto);
  }

  @Post('batches/:id/edit-requests')
  @Roles('OPERATOR', 'ADMIN')
  requestEdit(@CurrentUser() user: AuthUser, @Id() id: string, @Body() dto: EditRequestDto) {
    return this.batches.createEditRequest(user, id, dto);
  }

  @Get('edit-requests')
  @Roles('MANAGER', 'ADMIN')
  editRequests(@Query() q: ListEditRequestsQuery) {
    return this.batches.listEditRequests(q);
  }

  @Post('edit-requests/:id/approve')
  @HttpCode(200)
  @Roles('MANAGER', 'ADMIN')
  approve(@CurrentUser() user: AuthUser, @Id() id: string, @Body() dto: ReviewDto) {
    return this.batches.reviewEditRequest(user, id, true, dto.note);
  }

  @Post('edit-requests/:id/reject')
  @HttpCode(200)
  @Roles('MANAGER', 'ADMIN')
  reject(@CurrentUser() user: AuthUser, @Id() id: string, @Body() dto: ReviewDto) {
    return this.batches.reviewEditRequest(user, id, false, dto.note);
  }

  @Post('batches/:id/tags')
  @Roles('OPERATOR', 'ADMIN')
  tag(@CurrentUser() user: AuthUser, @Id() id: string, @Body() dto: AttachTagDto) {
    return this.batches.attachTag(user, id, dto);
  }

  @Post('batches/:id/images')
  @Roles('OPERATOR', 'ADMIN')
  image(@CurrentUser() user: AuthUser, @Id() id: string, @Body() dto: AttachImageDto) {
    return this.batches.attachImage(user, id, dto);
  }

  @Get('batches/:id/storage-path')
  storagePath(@CurrentUser() user: AuthUser, @Id() id: string) {
    return this.batches.storagePath(user, id);
  }

  @Post('batches/:id/storage')
  @HttpCode(200)
  @Roles('OPERATOR', 'ADMIN')
  store(@CurrentUser() user: AuthUser, @Id() id: string, @Body() dto: AssignStorageDto) {
    return this.batches.assignStorage(user, id, dto.storageUnitId);
  }

  @Get('batches/:id/label')
  label(@CurrentUser() user: AuthUser, @Id() id: string) {
    return this.batches.label(user, id);
  }

  @Post('batches/:id/receive')
  @HttpCode(200)
  @Roles('OPERATOR', 'ADMIN')
  receive(@CurrentUser() user: AuthUser, @Id() id: string, @Body() dto: ReceiveDto) {
    return this.batches.receive(user, id, dto);
  }

  @Get('batches/:id/timeline')
  timeline(@CurrentUser() user: AuthUser, @Id() id: string) {
    return this.batches.timeline(user, id);
  }

  @Get('batches/:id/shelf-life')
  shelfLife(@CurrentUser() user: AuthUser, @Id() id: string) {
    return this.batches.shelfLife(user, id);
  }
}
