import { Body, Controller, Delete, Get, Param, ParseUUIDPipe, Patch, Post, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { Roles } from '../../common/auth/decorators';
import { BuyersService } from './buyers.service';
import { CreateBuyerDto, ListBuyersQuery, UpdateBuyerDto } from './dto/buyer.dto';

@ApiTags('buyers')
@ApiBearerAuth()
@Roles('MANAGER', 'ADMIN')
@Controller('buyers')
export class BuyersController {
  constructor(private readonly buyers: BuyersService) {}

  @Get()
  list(@Query() q: ListBuyersQuery) {
    return this.buyers.list(q);
  }

  @Get(':id')
  get(@Param('id', ParseUUIDPipe) id: string) {
    return this.buyers.get(id);
  }

  @Post()
  create(@Body() dto: CreateBuyerDto) {
    return this.buyers.create(dto);
  }

  @Patch(':id')
  update(@Param('id', ParseUUIDPipe) id: string, @Body() dto: UpdateBuyerDto) {
    return this.buyers.update(id, dto);
  }

  /** Soft delete (`active=false`). */
  @Delete(':id')
  remove(@Param('id', ParseUUIDPipe) id: string) {
    return this.buyers.deactivate(id);
  }
}
