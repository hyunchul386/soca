/*
 * (C) Copyright 2017-2021 UCAR
 *
 * This software is licensed under the terms of the Apache Licence Version 2.0
 * which can be obtained at http://www.apache.org/licenses/LICENSE-2.0.
 */

#include <vector>

#include "soca/Traits.h"

#include "soca/Geometry/Geometry.h"
#include "soca/Model/mom6solo/Model.h"
#include "soca/Model/mom6solo/ModelFortran.h"
#include "soca/ModelBias/ModelBias.h"
#include "soca/State/State.h"

#include "eckit/config/Configuration.h"
#include "eckit/exception/Exceptions.h"

#include "oops/util/DateTime.h"
#include "oops/util/Logger.h"

using oops::Log;

namespace soca {
  // -----------------------------------------------------------------------------
  static oops::interface::ModelMaker<Traits, Model> makermodel_("MOM6solo");
  // -----------------------------------------------------------------------------
  Model::Model(const Geometry & resol, const eckit::Configuration & model)
    : keyConfig_(0),
      tstep_(0),
      geom_(resol),
      vars_(model, "model variables"),
      setup_mom6_(true)
  {
    Log::trace() << "Model::Model" << std::endl;
    Log::trace() << "Model vars: " << vars_ << std::endl;
    tstep_ = util::Duration(model.getString("tstep"));
    setup_mom6_ = model.getBool("setup_mom6", true);
    const eckit::Configuration * configc = &model;
    if (setup_mom6_)
      {
        soca_model_setup_f90(&configc, geom_.toFortran(), keyConfig_);
      }
        Log::trace() << "Model created" << std::endl;
  }
  // -----------------------------------------------------------------------------
  Model::~Model() {
    if (setup_mom6_)
      {
        soca_model_delete_f90(keyConfig_);
      }
    Log::trace() << "Model destructed" << std::endl;
  }
  // -----------------------------------------------------------------------------
  void Model::initialize(State & xx) const {
    soca_model_init_f90(keyConfig_, xx.toFortran());
    Log::debug() << "Model::initialize" << std::endl;
  }
  // -----------------------------------------------------------------------------
  void Model::step(State & xx, const ModelBias &) const {
    Log::trace() << "Model::Time: " << xx.validTime() << std::endl;
    util::DateTime * modeldate = &xx.validTime();
    soca_model_propagate_f90(keyConfig_, xx.toFortran(), &modeldate);
    xx.validTime() += tstep_;
  }
  // -----------------------------------------------------------------------------
  void Model::finalize(State & xx) const {
    soca_model_finalize_f90(keyConfig_, xx.toFortran());
    Log::debug() << "Model::finalize" << std::endl;
  }
  // -----------------------------------------------------------------------------
  int Model::saveTrajectory(State & xx, const ModelBias &) const {
    int ftraj = 0;
    xx.validTime() += tstep_;
    return ftraj;
  }
  // -----------------------------------------------------------------------------
  void Model::print(std::ostream & os) const {
    os << "Model::print not implemented";
  }
  // -----------------------------------------------------------------------------
}  // namespace soca
