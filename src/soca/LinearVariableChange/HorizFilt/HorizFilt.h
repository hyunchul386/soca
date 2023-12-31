/*
 * (C) Copyright 2017-2021  UCAR.
 *
 * This software is licensed under the terms of the Apache Licence Version 2.0
 * which can be obtained at http://www.apache.org/licenses/LICENSE-2.0.
 */

#pragma once

#include <memory>
#include <ostream>
#include <string>

#include "oops/base/Variables.h"
#include "oops/util/DateTime.h"
#include "oops/util/Printable.h"

#include "soca/LinearVariableChange/Base/LinearVariableChangeBase.h"

// Forward declarations
namespace eckit {
  class Configuration;
}
namespace soca {
  class Fields;
  class State;
  class Increment;
  class Geometry;
}

// -----------------------------------------------------------------------------

namespace soca {

/// SOCA linear change of variable
class HorizFilt: public LinearVariableChangeBase {
 public:
  static const std::string classname() {return "soca::HorizFilt";}

  explicit HorizFilt(const State &, const State &, const Geometry &,
                  const eckit::Configuration &);
  ~HorizFilt();

/// Perform linear transforms
  void multiply(const Increment &, Increment &) const;
  void multiplyInverse(const Increment &, Increment &) const;
  void multiplyAD(const Increment &, Increment &) const;
  void multiplyInverseAD(const Increment &, Increment &) const;

 private:
  void print(std::ostream &) const override;
  int keyFtnConfig_;
  const Geometry & geom_;
  oops::Variables vars_;
  unsigned int niter_;
};
// -----------------------------------------------------------------------------

}  // namespace soca
