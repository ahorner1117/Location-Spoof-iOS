import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        let model = Self.createModel()
        container = NSPersistentContainer(name: "LocationSpoof", managedObjectModel: model)

        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }

        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("CoreData failed to load: \(error)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    private static func createModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        let entity = NSEntityDescription()
        entity.name = "SavedLocation"
        entity.managedObjectClassName = "SavedLocation"

        let idAttr = NSAttributeDescription()
        idAttr.name = "id"
        idAttr.attributeType = .UUIDAttributeType
        idAttr.isOptional = false

        let nameAttr = NSAttributeDescription()
        nameAttr.name = "name"
        nameAttr.attributeType = .stringAttributeType
        nameAttr.isOptional = false

        let latAttr = NSAttributeDescription()
        latAttr.name = "latitude"
        latAttr.attributeType = .doubleAttributeType
        latAttr.isOptional = false

        let lngAttr = NSAttributeDescription()
        lngAttr.name = "longitude"
        lngAttr.attributeType = .doubleAttributeType
        lngAttr.isOptional = false

        let addressAttr = NSAttributeDescription()
        addressAttr.name = "address"
        addressAttr.attributeType = .stringAttributeType
        addressAttr.isOptional = true

        let createdAtAttr = NSAttributeDescription()
        createdAtAttr.name = "createdAt"
        createdAtAttr.attributeType = .dateAttributeType
        createdAtAttr.isOptional = false

        entity.properties = [idAttr, nameAttr, latAttr, lngAttr, addressAttr, createdAtAttr]
        model.entities = [entity]

        return model
    }
}
