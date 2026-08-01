# frozen_string_literal: true

# The XTEST keyboard injector now lives in the project, as spec support, since
# the RGame::Core spec suite uses it. This shim keeps the ad-hoc probe scripts
# in this directory working against that one implementation rather than a copy.
require_relative '../../../../spec_core/support/x_keys'
