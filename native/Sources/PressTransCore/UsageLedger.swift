import Foundation
import SQLite3

public struct UsageRecord:Sendable,Identifiable {
    public let id:String
    public let date:Date
    public let provider:String
    public let model:String
    public let detail:Bool
    public var status:String
    public var usage:TokenUsage?
    public init(id:String=UUID().uuidString,date:Date=Date(),provider:String,model:String,detail:Bool,status:String="running",usage:TokenUsage?=nil) {
        self.id=id;self.date=date;self.provider=String(provider.prefix(64));self.model=String(model.prefix(120));self.detail=detail;self.status=status;self.usage=usage
    }
}
public struct UsagePage:Sendable {
    public let records:[UsageRecord]
    public let count:Int
    public let total:Int
    public let today:Int
    public let unknown:Int
    public let bytes:Int64
}

/// A small local ledger: no queries, answers, credentials or endpoint URLs are stored.
public actor UsageLedger {
    private let db:OpaquePointer
    private let path:String
    public init(path:String) throws {
        var connection:OpaquePointer?
        guard sqlite3_open_v2(path,&connection,SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX,nil)==SQLITE_OK,let connection else {
            if let connection{sqlite3_close(connection)}
            throw CocoaError(.fileWriteUnknown)
        }
        do {
            try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:path)
            let sql="""
            PRAGMA journal_mode=DELETE;
            PRAGMA synchronous=NORMAL;
            PRAGMA cache_size=-256;
            PRAGMA mmap_size=0;
            PRAGMA busy_timeout=1000;
            CREATE TABLE IF NOT EXISTS requests (
              id TEXT PRIMARY KEY, started REAL NOT NULL, provider TEXT NOT NULL, model TEXT NOT NULL,
              detail INTEGER NOT NULL, status TEXT NOT NULL, input INTEGER, output INTEGER,
              total INTEGER, cached INTEGER, reasoning INTEGER);
            CREATE INDEX IF NOT EXISTS request_date ON requests(started DESC);
            UPDATE requests SET status='interrupted' WHERE status='running';
            """
            guard sqlite3_exec(connection,sql,nil,nil,nil)==SQLITE_OK else{throw CocoaError(.fileWriteUnknown)}
        } catch {sqlite3_close(connection);throw error}
        db=connection;self.path=path
    }
    deinit{sqlite3_close(db)}
    public func save(_ record:UsageRecord) throws {
        let sql="""
        INSERT INTO requests VALUES(?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET
        status=excluded.status,input=excluded.input,output=excluded.output,total=excluded.total,
        cached=excluded.cached,reasoning=excluded.reasoning;
        """
        var statement:OpaquePointer?
        guard sqlite3_prepare_v2(db,sql,-1,&statement,nil)==SQLITE_OK else{throw CocoaError(.fileWriteUnknown)}
        defer{sqlite3_finalize(statement)}
        let transient=unsafeBitCast(-1,to:sqlite3_destructor_type.self)
        func text(_ index:Int32,_ value:String){sqlite3_bind_text(statement,index,value,-1,transient)}
        func count(_ index:Int32,_ value:Int?){if let value {sqlite3_bind_int64(statement,index,Int64(value))}else{sqlite3_bind_null(statement,index)}}
        text(1,record.id);sqlite3_bind_double(statement,2,record.date.timeIntervalSince1970)
        text(3,record.provider);text(4,record.model);sqlite3_bind_int(statement,5,record.detail ? 1:0);text(6,record.status)
        count(7,record.usage?.input);count(8,record.usage?.output);count(9,record.usage?.total);count(10,record.usage?.cached);count(11,record.usage?.reasoning)
        guard sqlite3_step(statement)==SQLITE_DONE else{throw CocoaError(.fileWriteUnknown)}
    }
    public func page(offset:Int=0,limit:Int=50,dayStart:Date=Calendar.current.startOfDay(for:Date())) throws -> UsagePage {
        var statement:OpaquePointer?
        guard sqlite3_prepare_v2(db,"SELECT * FROM requests ORDER BY started DESC,rowid DESC LIMIT ? OFFSET ?",-1,&statement,nil)==SQLITE_OK else{throw CocoaError(.fileReadUnknown)}
        defer{sqlite3_finalize(statement)}
        sqlite3_bind_int(statement,1,Int32(min(max(limit,1),100)));sqlite3_bind_int64(statement,2,Int64(max(offset,0)))
        var records:[UsageRecord]=[]
        var step=sqlite3_step(statement)
        while step==SQLITE_ROW {
            func string(_ index:Int32)->String{sqlite3_column_text(statement,index).map{String(cString:$0)} ?? ""}
            func count(_ index:Int32)->Int?{sqlite3_column_type(statement,index)==SQLITE_NULL ? nil:Int(sqlite3_column_int64(statement,index))}
            let usage:TokenUsage?
            if let input=count(6),let output=count(7),let total=count(8){usage=TokenUsage(input:input,output:output,total:total,cached:count(9),reasoning:count(10))}else{usage=nil}
            records.append(UsageRecord(id:string(0),date:Date(timeIntervalSince1970:sqlite3_column_double(statement,1)),provider:string(2),model:string(3),detail:sqlite3_column_int(statement,4)==1,status:string(5),usage:usage))
            step=sqlite3_step(statement)
        }
        guard step==SQLITE_DONE else{throw CocoaError(.fileReadUnknown)}
        var summary:OpaquePointer?
        guard sqlite3_prepare_v2(db,"SELECT COUNT(*),COALESCE(SUM(total),0),COALESCE(SUM(CASE WHEN started>=? THEN total ELSE 0 END),0),COALESCE(SUM(CASE WHEN total IS NULL AND status!='running' THEN 1 ELSE 0 END),0) FROM requests",-1,&summary,nil)==SQLITE_OK else{throw CocoaError(.fileReadUnknown)}
        defer{sqlite3_finalize(summary)}
        sqlite3_bind_double(summary,1,dayStart.timeIntervalSince1970)
        guard sqlite3_step(summary)==SQLITE_ROW else{throw CocoaError(.fileReadUnknown)}
        let bytes=(try? FileManager.default.attributesOfItem(atPath:path)[.size] as? NSNumber)?.int64Value ?? 0
        return UsagePage(records:records,count:Int(sqlite3_column_int64(summary,0)),total:Int(sqlite3_column_int64(summary,1)),today:Int(sqlite3_column_int64(summary,2)),unknown:Int(sqlite3_column_int64(summary,3)),bytes:bytes)
    }
}
