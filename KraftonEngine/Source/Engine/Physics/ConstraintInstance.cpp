#include "ConstraintInstance.h"

float FConstraintInstance::GetTwistLimitRadians() const
{
	return TwistLimitDegrees * FMath::DegToRad;
}

float FConstraintInstance::GetSwing1LimitRadians() const
{
	return Swing1LimitDegrees * FMath::DegToRad;
}

float FConstraintInstance::GetSwing2LimitRadians() const
{
	return Swing2LimitDegrees * FMath::DegToRad;
}
