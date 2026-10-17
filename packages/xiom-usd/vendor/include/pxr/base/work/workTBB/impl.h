//
// Copyright 2025 Pixar
//
// Licensed under the terms set forth in the LICENSE.txt file available at
// https://openusd.org/license.
//
#ifndef PXR_BASE_WORK_TBB_IMPL_H
#define PXR_BASE_WORK_TBB_IMPL_H

/// This file pulls in the entire work implementation

#include "detachedTask_impl.h"
#include "dispatcher_impl.h"
#include "isolatingDispatcher_impl.h"
#include "loops_impl.h"
#include "reduce_impl.h"
#include "sort_impl.h"
#include "taskGraph_impl.h"
#include "threadLimits_impl.h"
#include "withScopedParallelism_impl.h"

#include "../../../pxr.h"
#if PXR_USE_NAMESPACES
#define WORK_IMPL_NS PXR_NS
#endif

#endif // PXR_BASE_WORK_TBB_IMPL_H
