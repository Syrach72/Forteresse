export const INITIAL_TRAINING = {
  instructor: { heroId: "gnaeus", remaining: 2 },
  students: [{ heroId: "hetamon", remaining: 0 }, null, null],
  capacity: 1,
  secondGroup: false,
};
export function stepTraining(state, delta) {
  return {
    ...state,
    instructor: state.instructor
      ? {
          ...state.instructor,
          remaining: Math.max(0, Math.min(5, state.instructor.remaining + delta)),
        }
      : null,
    students: state.students.map((s) =>
      s ? { ...s, remaining: Math.max(0, Math.min(5, s.remaining + delta)) } : null,
    ),
  };
}
export function trainingIds(state) {
  return [state.instructor, ...state.students]
    .filter(Boolean)
    .map((x) => x.heroId);
}
