//
//  File.swift
//  
//
//  Created by Jimmy McDermott on 10/11/20.
//

import Foundation
import Vapor
import Fluent
import QueuesDatabaseHooks
import SQLKit

struct DashboardController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        routes.get(use: dashboard)
    }

    func dashboard(req: Request) -> EventLoopFuture<View> {
        let hours = (try? req.query.get(Int.self, at: "hours")) ?? 1
        let currentJobsQuery = QueueDatabaseEntry.getStatusOfCurrentJobs(db: req.db)
        let completedJobsQuery = QueueDatabaseEntry.getCompletedJobsForTimePeriod(db: req.db, hours: hours)
        let timingQuery = QueueDatabaseEntry.getTimingDataForJobs(db: req.db, hours: hours)

        return currentJobsQuery.and(completedJobsQuery).and(timingQuery).flatMap { currentCompleted, timing in
            return getGraphData(req: req).flatMap { throughput, execution in
                return req.view.render("dashboard", DashboardViewContext(currentJobData: currentCompleted.0,
                                                                         completedJobData: currentCompleted.1,
                                                                         timingData: timing,
                                                                         hours: hours,
                                                                         throughputValues: throughput,
                                                                         executionTimeValues: execution))
            }
        }
    }

    private func getGraphData(req: Request) -> EventLoopFuture<(throughput: [DashboardViewContext.GraphData], execution: [DashboardViewContext.GraphData])> {
        let executionQuery: SQLQueryString = """
        SELECT
            EXTRACT(EPOCH FROM AVG("completedAt" - "dequeuedAt")) AS "value",
            TO_CHAR("completedAt", 'HH24:00') AS "key"
        FROM
            _queue_job_completions
        WHERE
            "completedAt" IS NOT NULL
            AND "completedAt" >= (NOW() - INTERVAL '24 hour')
        GROUP BY
            TO_CHAR("completedAt", 'HH24:00');
        """

        let throughputQuery: SQLQueryString = """
        SELECT
            COUNT(*) * 1.0 AS "value",
            TO_CHAR("completedAt", 'HH24:00') AS "key"
        FROM
            "_queue_job_completions"
        WHERE
            "completedAt" IS NOT NULL
            AND "completedAt" >= (NOW() - INTERVAL '24 hour')
        GROUP BY
            TO_CHAR("completedAt", 'HH24:00');
        """

        guard let sqlDb = req.db as? SQLDatabase else { return req.eventLoop.future(error: Abort(.internalServerError)) }
        return sqlDb
            .raw(executionQuery)
            .all(decoding: DashboardViewContext.GraphData.self)
            .and(sqlDb.raw(throughputQuery).all(decoding: DashboardViewContext.GraphData.self))
            .map { execution, throughput in
                return (throughput, execution)
            }
    }
}
