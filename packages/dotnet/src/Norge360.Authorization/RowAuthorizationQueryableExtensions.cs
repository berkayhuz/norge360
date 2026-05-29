// <copyright file="RowAuthorizationQueryableExtensions.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Linq.Expressions;

namespace Norge360.Authorization;

public static class RowAuthorizationQueryableExtensions
{
    public static IQueryable<T> ApplyRowScope<T>(
        this IQueryable<T> query,
        AuthorizationScope scope,
        Expression<Func<T, Guid?>> ownerUserIdSelector,
        Expression<Func<T, Guid?>> assignedUserIdSelector)
    {
        var parameter = ownerUserIdSelector.Parameters[0];
        var userId = Expression.Constant(scope.UserId, typeof(Guid?));
        var ownerMatch = Expression.Equal(ownerUserIdSelector.Body, userId);
        var assignedBody = assignedUserIdSelector.Parameters[0] == parameter
            ? assignedUserIdSelector.Body
            : ReplaceParameter(assignedUserIdSelector.Body, assignedUserIdSelector.Parameters[0], parameter);
        var assignedMatch = Expression.Equal(assignedBody, userId);
        var scopedBody = scope.RowAccessLevel >= RowAccessLevel.Assigned
            ? Expression.OrElse(ownerMatch, assignedMatch)
            : ownerMatch;

        return query.Where(Expression.Lambda<Func<T, bool>>(scopedBody, parameter));
    }

    private static Expression ReplaceParameter(Expression expression, ParameterExpression source, ParameterExpression target) =>
        new ParameterReplaceVisitor(source, target).Visit(expression) ?? expression;

    private sealed class ParameterReplaceVisitor(ParameterExpression source, ParameterExpression target) : ExpressionVisitor
    {
        protected override Expression VisitParameter(ParameterExpression node) =>
            node == source ? target : base.VisitParameter(node);
    }
}
