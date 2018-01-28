#ifndef SOCA_MODEL_SOCATRAITS_H_
#define SOCA_MODEL_SOCATRAITS_H_

#include <string>

#include "model/ModelBias.h"
#include "model/ModelBiasIncrement.h"
#include "model/ModelBiasCovariance.h"
#include "model/Geometry/Geometry.h"
#include "model/Increment/Increment.h"
#include "model/Model/Model.h"
#include "model/State/State.h"

#include "ufo/GeoVaLs.h"
#include "ufo/Locations.h"
#include "ufo/ObsSpace.h"
#include "ufo/ObsVector.h"
#include "ufo/ObsBias.h"
#include "ufo/ObsBiasIncrement.h"
#include "ufo/ObsCheck.h"
//#include "ufo/ObsBiasCovarance.h"

namespace soca {

struct Traits {
  static std::string name() {return "SOCA";}

  typedef soca::Geometry            Geometry;
  typedef soca::State               State;
  typedef soca::Model               Model;
  typedef soca::Increment           Increment;

  typedef soca::ModelBias           ModelAuxControl;
  typedef soca::ModelBiasIncrement  ModelAuxIncrement;
  typedef soca::ModelBiasCovariance ModelAuxCovariance;

  typedef ufo::ObsBias              ObsAuxControl;
  typedef ufo::ObsBiasIncrement     ObsAuxIncrement;
  //typedef ufo::ObsBiasCovariance    ObsAuxCovariance;
  
  typedef ufo::ObsCheck             ObsCheck;  

  typedef ufo::GeoVaLs              GeoVaLs;
  typedef ufo::Locations            Locations;
  typedef ufo::ObsSpace             ObsSpace;
  typedef ufo::ObsVector            ObsVector;
};

}  // namespace soca

#endif  // SOCA_MODEL_SOCATRAITS_H_
