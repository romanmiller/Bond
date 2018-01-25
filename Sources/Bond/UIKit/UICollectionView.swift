//
//  The MIT License (MIT)
//
//  Copyright (c) 2016 Srdan Rasic (@srdanrasic)
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

#if os(iOS) || os(tvOS)

import UIKit
import ReactiveKit

public protocol CollectionViewBond {
    associatedtype DataSource: DataSourceProtocol
    func cellForRow(at indexPath: IndexPath, collectionView: UICollectionView, dataSource: DataSource) -> UICollectionViewCell
}

public protocol CollectionViewBondDelegate {
    associatedtype DataSource: DataSourceProtocol
    
    func sizeForRow(at indexPath: IndexPath, collectionView: UICollectionView, dataSource: DataSource) -> CGSize
    func didSelectRow(at indexPath: IndexPath, collectionView: UICollectionView, dataSource: DataSource)
}

private struct SimpleCollectionViewBond<DataSource: DataSourceProtocol>: CollectionViewBond {

    let createCell: (DataSource, IndexPath, UICollectionView) -> UICollectionViewCell

    func cellForRow(at indexPath: IndexPath, collectionView: UICollectionView, dataSource: DataSource) -> UICollectionViewCell {
        return createCell(dataSource, indexPath, collectionView)
    }
}

public extension ReactiveExtensions where Base: UICollectionViewCell {
    public var isSelected: DynamicSubject<Bool> {
        return keyPath("selected", ofType: Bool.self)
    }
}
    
public extension ReactiveExtensions where Base: UICollectionView {

    public var delegate: ProtocolProxy {
        return protocolProxy(for: UICollectionViewDelegateFlowLayout.self, keyPath: \.delegate)
    }

    public var dataSource: ProtocolProxy {
        return protocolProxy(for: UICollectionViewDataSource.self, keyPath: \.dataSource)
    }
}

public extension SignalProtocol where Element: DataSourceEventProtocol, Element.BatchKind == BatchKindDiff, Error == NoError {

    @discardableResult
    public func bind(to collectionView: UICollectionView, createCell: @escaping (DataSource, IndexPath, UICollectionView) -> UICollectionViewCell) -> Disposable {
        return bind(to: collectionView, using: SimpleCollectionViewBond<DataSource>(createCell: createCell))
    }
    
    
    @discardableResult
    public func bind2<B: CollectionViewBond>(to collectionView: UICollectionView, using bond: B) -> Disposable where B.DataSource == DataSource, B:CollectionViewBondDelegate {
        let disposable = CompositeDisposable()
        let dataSource = Property<DataSource?>(nil)
        disposable += _bind(to: collectionView, using: bond, and: dataSource)
        disposable += _bound(with: collectionView, to: bond, and: dataSource)
        return disposable
    }
    
    @discardableResult
    private func _bound<D:CollectionViewBondDelegate>(with collectionView: UICollectionView, to delegate:D, and dataSource: Property<DataSource?>) -> Disposable where D.DataSource == DataSource {
        
        let disposable = CompositeDisposable()
        disposable += collectionView.reactive.delegate.feed(
            property: dataSource,
            to: #selector(UICollectionViewDelegateFlowLayout.collectionView(_:layout:sizeForItemAt:)),
            map: { (dataSource: DataSource?, collectionView: UICollectionView, layout: UICollectionViewLayout, indexPath: IndexPath) -> CGSize in
                return delegate.sizeForRow(at: indexPath as IndexPath, collectionView: collectionView, dataSource: dataSource!)
        })
        
        disposable += collectionView.reactive.delegate.feed(
            property: dataSource,
            to: #selector(UICollectionViewDelegate.collectionView(_:didSelectItemAt:)),
            map: { (dataSource: DataSource?, collectionView: UICollectionView, indexPath: IndexPath) in
                return delegate.didSelectRow(at: indexPath as IndexPath, collectionView: collectionView, dataSource: dataSource!)
        })
        
        
        return disposable
    }
    
    @discardableResult
    public func bind<B: CollectionViewBond>(to collectionView: UICollectionView, using bond: B) -> Disposable where B.DataSource == DataSource {
        let dataSource = Property<DataSource?>(nil)
        return _bind(to: collectionView, using: bond, and: dataSource)
        
    }
    private func _bind<B: CollectionViewBond>(to collectionView: UICollectionView, using bond: B, and dataSource: Property<DataSource?>) -> Disposable where B.DataSource == DataSource {
        
        let disposable = CompositeDisposable()
        
        disposable += collectionView.reactive.dataSource.feed(
            property: dataSource,
            to: #selector(UICollectionViewDataSource.collectionView(_:cellForItemAt:)),
            map: { (dataSource: DataSource?, collectionView: UICollectionView, indexPath: NSIndexPath) -> UICollectionViewCell in
                return bond.cellForRow(at: indexPath as IndexPath, collectionView: collectionView, dataSource: dataSource!)
        }
        )
        
        disposable += collectionView.reactive.dataSource.feed(
            property: dataSource,
            to: #selector(UICollectionViewDataSource.collectionView(_:numberOfItemsInSection:)),
            map: { (dataSource: DataSource?, _: UICollectionView, section: Int) -> Int in dataSource?.numberOfItems(inSection: section) ?? 0 }
        )
        
        disposable += collectionView.reactive.dataSource.feed(
            property: dataSource,
            to: #selector(UICollectionViewDataSource.numberOfSections(in:)),
            map: { (dataSource: DataSource?, _: UICollectionView) -> Int in dataSource?.numberOfSections ?? 0 }
        )
        
        var bufferedEvents: [DataSourceEventKind]? = nil
        
        disposable += bind(to: collectionView) { collectionView, event in
            dataSource.value = event.dataSource
            
            let applyEventOfKind: (DataSourceEventKind) -> () = { kind in
                switch kind {
                case .reload:
                    collectionView.reloadData()
                case .insertItems(let indexPaths):
                    collectionView.insertItems(at: indexPaths)
                case .deleteItems(let indexPaths):
                    collectionView.deleteItems(at: indexPaths)
                case .reloadItems(let indexPaths):
                    collectionView.reloadItems(at: indexPaths)
                case .moveItem(let indexPath, let newIndexPath):
                    collectionView.moveItem(at: indexPath, to: newIndexPath)
                case .insertSections(let indexSet):
                    collectionView.insertSections(indexSet)
                case .deleteSections(let indexSet):
                    collectionView.deleteSections(indexSet)
                case .reloadSections(let indexSet):
                    collectionView.reloadSections(indexSet)
                case .moveSection(let index, let newIndex):
                    collectionView.moveSection(index, toSection: newIndex)
                case .beginUpdates:
                    fatalError()
                case .endUpdates:
                    fatalError()
                }
            }
            
            switch event.kind {
            case .reload:
                collectionView.reloadData()
            case .beginUpdates:
                bufferedEvents = []
            case .endUpdates:
                if let bufferedEvents = bufferedEvents {
                    collectionView.performBatchUpdates({ bufferedEvents.forEach(applyEventOfKind) }, completion: nil)
                } else {
                    fatalError("Bond: Unexpected event .endUpdates. Should have been preceded by a .beginUpdates event.")
                }
                bufferedEvents = nil
            default:
                if bufferedEvents != nil {
                    bufferedEvents!.append(event.kind)
                } else {
                    applyEventOfKind(event.kind)
                }
            }
        }
        
        return disposable
    }
}

#endif
