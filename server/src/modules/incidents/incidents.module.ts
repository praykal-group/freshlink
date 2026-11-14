import { Global, Module } from '@nestjs/common';
import { OfferPageController } from '../diversions/offer-page.controller';
import { OffersService } from '../diversions/offers.service';
import { ReroutingService } from '../diversions/rerouting.service';
import { ShelfLifeModule } from '../shelf-life/shelf-life.module';
import { IncidentsController } from './incidents.controller';
import { IncidentsService } from './incidents.service';

const providers = [IncidentsService, OffersService, ReroutingService];

/** Worker: the engine, offers and rerouting, without HTTP controllers. */
@Global()
@Module({ imports: [ShelfLifeModule], providers, exports: providers })
export class IncidentsCoreModule {}

/** API: same services + manager endpoints and the public offer page. */
@Global()
@Module({ imports: [ShelfLifeModule], controllers: [IncidentsController, OfferPageController], providers, exports: providers })
export class IncidentsModule {}
