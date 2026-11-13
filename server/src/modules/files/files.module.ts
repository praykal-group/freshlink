import { Module } from '@nestjs/common';
import { S3Service } from '../../infra/s3/s3.service';
import { FilesController } from './files.controller';
import { FilesService } from './files.service';

@Module({ controllers: [FilesController], providers: [FilesService, S3Service], exports: [FilesService] })
export class FilesModule {}
