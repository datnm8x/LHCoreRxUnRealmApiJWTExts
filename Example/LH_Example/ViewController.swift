import UIKit
import RealmSwift
import RxCocoa
import RxSwift
import LHCoreRxRealmApiJWTExts

// view controller
class ViewController: UIViewController {
    let bag = DisposeBag()
    
    @IBOutlet var tableView: UITableView!
    @IBOutlet var tickItemButton: UIBarButtonItem!
    @IBOutlet var addTwoItemsButton: UIBarButtonItem!
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
}

extension UITableView {
    /*
    func applyChangeset(_ changes: RealmChangeset) {
        beginUpdates()
        deleteRows(at: changes.deleted.map { IndexPath(row: $0, section: 0) }, with: .automatic)
        insertRows(at: changes.inserted.map { IndexPath(row: $0, section: 0) }, with: .automatic)
        reloadRows(at: changes.updated.map { IndexPath(row: $0, section: 0) }, with: .automatic)
        endUpdates()
    }
 */
}

